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
/// The service is intentionally database-agnostic: POS debt/balance remains on
/// the POS customer account, so this feature does not introduce a second POS
/// financial ledger.
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

  /// Sends yesterday's summary once per POS per application day.
  ///
  /// Calling this method repeatedly is safe because the successful send marker
  /// is persisted after the message succeeds.
  Future<Result<PosDailySummaryReport>> sendDue({DateTime? now}) async {
    final enabledSetting = await settings.find(
      SettingKeys.dailyOpsSummaryAutoSend,
    );
    if (enabledSetting is Failure<AppSetting?>) {
      return Failure(enabledSetting.error);
    }

    final enabled = SettingBool.read(
      (enabledSetting as Success<AppSetting?>).value?.value,
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

    final accountsResult = await posRegistry.listAll();
    if (accountsResult is Failure<List<PosAccount>>) {
      return Failure(accountsResult.error);
    }

    final completed = await transactions.listCompleted(currencyCode: 'YER');
    if (completed is Failure<List<Transaction>>) {
      return Failure(completed.error);
    }
    final rows = (completed as Success<List<Transaction>>).value;

    final template = await _loadTemplate();
    if (template is Failure<String>) {
      return Failure(template.error);
    }
    final templateText = (template as Success<String>).value;

    var sent = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (final account in accountsResult.value) {
      if (account.status != PointOfSaleStatus.active) {
        skipped++;
        continue;
      }

      final markerKey = 'pos_daily_summary:${account.posId}:$dayKey';
      final marker = await settings.find(markerKey);
      if (marker is Failure<AppSetting?>) {
        failed++;
        errors.add('${account.posId}:marker_read_failed');
        continue;
      }
      if ((marker as Success<AppSetting?>).value != null) {
        skipped++;
        continue;
      }

      final accountRows = rows.where(
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

      final balance = await balances.getBalance(
        customerId: account.customerId,
        currencyCode: 'YER',
      );
      if (balance is Failure) {
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
        templateText,
        pos: account.name,
        salesMinorUnits: salesMinorUnits,
        transferMinorUnits: transferMinorUnits,
        balanceMinorUnits: (balance as Success).value.minorUnits,
      );

      final sentResult = await messageSender.send(
        destination: destination,
        body: body,
      );
      if (sentResult is Failure<void>) {
        failed++;
        errors.add('${account.posId}:${sentResult.error.code}');
        await _auditFailure(
          account: account,
          day: summaryDay,
          code: sentResult.error.code.isEmpty
              ? 'sms_send_failed'
              : sentResult.error.code,
        );
        continue;
      }

      final markerSave = await settings.save(
        AppSetting(
          key: markerKey,
          value: 'sent:${ids.next('pos-summary')}',
          updatedAt: clock.now(),
        ),
      );
      if (markerSave is Failure<void>) {
        failed++;
        errors.add('${account.posId}:marker_write_failed');
        await _auditFailure(
          account: account,
          day: summaryDay,
          code: 'marker_write_failed',
        );
        continue;
      }

      final audit = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'pos_account',
          entityId: account.posId,
          action: 'pos_daily_summary_sent',
          occurredAt: clock.now(),
          payloadJson:
              '${{"day":"${_dayKey(summaryDay)}","destination":"${destination}","salesMinorUnits":$salesMinorUnits,"transferMinorUnits":$transferMinorUnits}}',
        ),
      );
      if (audit is Failure<void>) {
        failed++;
        errors.add('${account.posId}:audit_write_failed');
        continue;
      }

      sent++;
    }

    return Success(
      PosDailySummaryReport(
        sent: sent,
        skipped: skipped,
        failed: failed,
        errors: errors,
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
        payloadJson:
            '${{"day":"${_dayKey(day)}","error":"${code}"}}',
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
