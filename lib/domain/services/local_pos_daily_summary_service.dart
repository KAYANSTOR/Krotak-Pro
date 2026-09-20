import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/pos_account.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import 'local_pos_account_registry.dart';
import 'services.dart';

/// Sends the configured daily POS operational summary from the same customer
/// ledger already used by the rest of the application.
///
/// POS debt/balance remains on the POS customer account. This feature therefore
/// does not create a second financial ledger just for POS summaries.
final class LocalPosDailySummaryService {
  const LocalPosDailySummaryService({
    required this.posRegistry,
    required this.transactions,
    required this.balances,
    required this.settings,
    required this.auditLogs,
    required this.messageSender,
    required this.clock,
    required this.ids,
  });

  final LocalPosAccountRegistry posRegistry;
  final TransactionRepository transactions;
  final CustomerBalanceService balances;
  final SettingsRepository settings;
  final AuditLogRepository auditLogs;
  final MessageSender messageSender;
  final Clock clock;
  final IdGenerator ids;

  /// Sends yesterday's summary once per POS for the current application day.
  ///
  /// Both a persisted marker and the audit trail act as idempotency fences.
  /// This prevents a successful SMS from being sent again when one of the
  /// post-send persistence writes fails.
  Future<Result<PosDailySummaryReport>> sendDue({DateTime? now}) async {
    final enabledResult = await settings.find(
      SettingKeys.dailyOpsSummaryAutoSend,
    );
    if (enabledResult is Failure<AppSetting?>) {
      return Failure(enabledResult.error);
    }

    final enabled = SettingBool.read(
      (enabledResult as Success<AppSetting?>).value?.value,
      defaultValue: SettingDefaults.dailyOpsSummaryAutoSend,
    );
    if (!enabled) {
      return const Success(
        PosDailySummaryReport(
          sent: 0,
          skipped: 0,
          failed: 0,
          errors: <String>[],
        ),
      );
    }

    final current = (now ?? clock.now()).toLocal();
    final summaryDay = DateTime(current.year, current.month, current.day - 1);
    final dayKey = _dayKey(current);
    final summaryDayKey = _dayKey(summaryDay);

    final accountsResult = await posRegistry.listAll();
    if (accountsResult is Failure<List<PosAccount>>) {
      return Failure(accountsResult.error);
    }
    final accounts = (accountsResult as Success<List<PosAccount>>).value;

    var sent = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];
    final dueAccounts = <({PosAccount account, String markerKey})>[];

    // The background recovery loop runs frequently for SMS reliability. Keep
    // the daily summary path cheap when every active POS has already been sent.
    for (final account in accounts) {
      if (account.status != PointOfSaleStatus.active) {
        skipped++;
        continue;
      }

      final markerKey = 'pos_daily_summary:${account.posId}:$dayKey';
      final markerResult = await settings.find(markerKey);
      if (markerResult is Failure<AppSetting?>) {
        failed++;
        errors.add('${account.posId}:marker_read_failed');
        continue;
      }
      if ((markerResult as Success<AppSetting?>).value != null) {
        skipped++;
        continue;
      }

      // Recovery fence: a successful audit entry means the SMS was already
      // sent even if the lightweight settings marker was not persisted.
      final auditResult = await auditLogs.findByEntity(
        'pos_account',
        account.posId,
      );
      if (auditResult is Failure<List<AuditLog>>) {
        failed++;
        errors.add('${account.posId}:audit_read_failed');
        continue;
      }
      final alreadyAudited =
          (auditResult as Success<List<AuditLog>>).value.any(
        (log) =>
            log.action == 'pos_daily_summary_sent' &&
            (log.payloadJson ?? '').contains('"day":"$summaryDayKey"'),
      );
      if (alreadyAudited) {
        skipped++;
        await settings.save(
          AppSetting(
            key: markerKey,
            value: 'sent:${ids.next('pos-summary-repair')}',
            updatedAt: clock.now(),
          ),
        );
        continue;
      }

      dueAccounts.add((account: account, markerKey: markerKey));
    }

    if (dueAccounts.isEmpty) {
      return Success(
        PosDailySummaryReport(
          sent: sent,
          skipped: skipped,
          failed: failed,
          errors: List.unmodifiable(errors),
        ),
      );
    }

    final completedResult = await transactions.listCompleted(
      currencyCode: 'YER',
    );
    if (completedResult is Failure<List<Transaction>>) {
      return Failure(completedResult.error);
    }
    final transactionsSnapshot =
        (completedResult as Success<List<Transaction>>).value;

    final templateResult = await _loadTemplate();
    if (templateResult is Failure<String>) {
      return Failure(templateResult.error);
    }
    final template = (templateResult as Success<String>).value;

    for (final due in dueAccounts) {
      final account = due.account;
      final markerKey = due.markerKey;

      final accountRows = transactionsSnapshot.where(
        (row) =>
            row.customerId == account.customerId &&
            row.amount.currencyCode == 'YER',
      );
      final salesMinorUnits = _sumForDay(
        accountRows,
        summaryDay,
        TransactionType.sale,
      );
      final transferMinorUnits = _sumForDay(
        accountRows,
        summaryDay,
        TransactionType.deposit,
      );

      final balanceResult = await balances.getBalance(
        customerId: account.customerId,
        currencyCode: 'YER',
      );
      if (balanceResult is Failure) {
        failed++;
        errors.add('${account.posId}:balance_read_failed');
        await _auditFailure(
          account: account,
          day: summaryDay,
          code: 'balance_read_failed',
        );
        continue;
      }

      final destination = _destinationFor(account);
      if (destination == null) {
        skipped++;
        continue;
      }

      final body = _render(
        template,
        pos: account.name,
        salesMinorUnits: salesMinorUnits,
        transferMinorUnits: transferMinorUnits,
        balanceMinorUnits:
            (balanceResult as Success).value.minorUnits,
      );

      final sendResult = await messageSender.send(
        destination: destination,
        body: body,
      );
      if (sendResult is Failure<void>) {
        failed++;
        final code = sendResult.error.code.isEmpty
            ? 'sms_send_failed'
            : sendResult.error.code;
        errors.add('${account.posId}:$code');
        await _auditFailure(
          account: account,
          day: summaryDay,
          code: code,
        );
        continue;
      }

      final auditResultAfterSend = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'pos_account',
          entityId: account.posId,
          action: 'pos_daily_summary_sent',
          occurredAt: clock.now(),
          payloadJson: jsonEncode(<String, Object?>{
            'day': summaryDayKey,
            'destination': destination,
            'salesMinorUnits': salesMinorUnits,
            'transferMinorUnits': transferMinorUnits,
          }),
        ),
      );

      final markerSave = await settings.save(
        AppSetting(
          key: markerKey,
          value: 'sent:${ids.next('pos-summary')}',
          updatedAt: clock.now(),
        ),
      );

      // The message has already been accepted by the sender. Persist at least
      // one idempotency fence before allowing another run to continue.
      if (auditResultAfterSend is Failure<void> &&
          markerSave is Failure<void>) {
        failed++;
        errors.add(
          '${account.posId}:post_send_persistence_failed',
        );
        // Best effort diagnostic. The next run may retry only if neither fence
        // could be persisted.
        await _auditFailure(
          account: account,
          day: summaryDay,
          code: 'post_send_persistence_failed',
        );
        continue;
      }

      if (auditResultAfterSend is Failure<void>) {
        failed++;
        errors.add('${account.posId}:audit_write_failed');
      }
      if (markerSave is Failure<void>) {
        failed++;
        errors.add('${account.posId}:marker_write_failed');
      }

      sent++;
    }

    return Success(
      PosDailySummaryReport(
        sent: sent,
        skipped: skipped,
        failed: failed,
        errors: List.unmodifiable(errors),
      ),
    );
  }

  Future<Result<String>> _loadTemplate() async {
    final found = await settings.find(SettingKeys.dailyPosSummaryTemplate);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final value = (found as Success<AppSetting?>).value?.value.trim();
    if (value == null || value.isEmpty) {
      return const Success(SettingDefaults.dailyPosSummaryTemplate);
    }
    return Success(value);
  }

  String? _destinationFor(PosAccount account) {
    final candidates = <String>[
      if (account.notifyPhone != null) account.notifyPhone!,
      ...account.identifiers,
    ];
    for (final raw in candidates) {
      final canonical = PhoneNormalizer.canonicalize(raw);
      if (canonical != null && canonical.isNotEmpty) return canonical;
    }
    return null;
  }

  int _sumForDay(
    Iterable<Transaction> rows,
    DateTime day,
    TransactionType type,
  ) {
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    var total = 0;

    for (final row in rows) {
      final local = row.createdAt.toLocal();
      if (row.type != type || row.status != TransactionStatus.completed) {
        continue;
      }
      if (local.isBefore(from) || !local.isBefore(to)) continue;
      total += row.amount.minorUnits;
    }

    return total;
  }

  String _render(
    String template, {
    required String pos,
    required int salesMinorUnits,
    required int transferMinorUnits,
    required int balanceMinorUnits,
  }) {
    final values = <String, String>{
      'pos': pos,
      'sales': _displayMinor(salesMinorUnits),
      'transfers': _displayMinor(transferMinorUnits),
      'balance': _displayMinor(balanceMinorUnits),
      'CURRENCY': 'ر.ي',
    };

    var result = template;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  String _displayMinor(int minorUnits) =>
      (minorUnits / 100).toStringAsFixed(2);

  String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _auditFailure({
    required PosAccount account,
    required DateTime day,
    required String code,
  }) async {
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'pos_account',
        entityId: account.posId,
        action: 'pos_daily_summary_failed',
        occurredAt: clock.now(),
        payloadJson: jsonEncode(<String, Object?>{
          'day': _dayKey(day),
          'error': code,
        }),
      ),
    );
  }
}
 
final class PosDailySummaryReport {
  const PosDailySummaryReport({
    required this.sent,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int sent;
  final int skipped;
  final int failed;
  final List<String> errors;
}
