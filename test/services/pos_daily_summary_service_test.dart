import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_pos_daily_summary_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  test('sends yesterday summary from the shared POS customer ledger', () async {
    final settings = _Settings({
      SettingKeys.dailyOpsSummaryAutoSend: 'true',
      SettingKeys.dailyPosSummaryTemplate:
          'POS={pos}|sales={sales}|transfers={transfers}|balance={balance}',
      SettingKeys.posAccounts:
          '[{"posId":"pos-1","customerId":"customer-1","name":"نقطة صنعاء","identifiers":["777123456"],"notifyPhone":"777123456","status":"active","percentageMode":"defaultCategory"}]',
    });

    final transactions = _Transactions([
      Transaction(
        id: 'sale-yesterday',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 500, currencyCode: 'YER'),
        createdAt: DateTime(2026, 9, 20, 10),
        customerId: 'customer-1',
      ),
      Transaction(
        id: 'deposit-yesterday',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 1200, currencyCode: 'YER'),
        createdAt: DateTime(2026, 9, 20, 12),
        customerId: 'customer-1',
      ),
      Transaction(
        id: 'sale-other-day',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 9999, currencyCode: 'YER'),
        createdAt: DateTime(2026, 9, 19, 10),
        customerId: 'customer-1',
      ),
    ]);
    final sender = _Sender();
    final audits = _Audits();
    final service = LocalPosDailySummaryService(
      posRegistry: LocalPosAccountRegistry(settings: settings, clock: FixedClock(DateTime(2026, 9, 21, 8))),
      transactions: transactions,
      balances: _Balances(
        const Money(minorUnits: 700, currencyCode: 'YER'),
      ),
      settings: settings,
      auditLogs: audits,
      messageSender: sender,
      clock: FixedClock(DateTime(2026, 9, 21, 8)),
      ids: SequentialIdGenerator(),
    );

    final result = await service.sendDue(
      now: DateTime(2026, 9, 21, 8),
    );

    expect(result, isA<Success<PosDailySummaryReport>>());
    final report = (result as Success<PosDailySummaryReport>).value;
    expect(report.sent, 1);
    expect(report.failed, 0);
    expect(sender.calls, 1);
    expect(sender.lastDestination, '777123456');
    expect(
      sender.lastBody,
      'POS=نقطة صنعاء|sales=5.00|transfers=12.00|balance=7.00',
    );
    expect(audits.entries, hasLength(1));
    expect(audits.entries.single.action, 'pos_daily_summary_sent');
  });

  test('does not send the same daily summary twice', () async {
    final settings = _Settings({
      SettingKeys.dailyOpsSummaryAutoSend: 'true',
      SettingKeys.dailyPosSummaryTemplate: 'ملخص {pos}',
      SettingKeys.posAccounts:
          '[{"posId":"pos-1","customerId":"customer-1","name":"نقطة 1","identifiers":["777123456"],"notifyPhone":"777123456","status":"active","percentageMode":"defaultCategory"}]',
    });
    final sender = _Sender();
    final audits = _Audits();
    final service = LocalPosDailySummaryService(
      posRegistry: LocalPosAccountRegistry(settings: settings, clock: FixedClock(DateTime(2026, 9, 21, 8))),
      transactions: _Transactions(const []),
      balances: _Balances(const Money(minorUnits: 0, currencyCode: 'YER')),
      settings: settings,
      auditLogs: audits,
      messageSender: sender,
      clock: FixedClock(DateTime(2026, 9, 21, 8)),
      ids: SequentialIdGenerator(),
    );

    final first = await service.sendDue(now: DateTime(2026, 9, 21, 8));
    final second = await service.sendDue(now: DateTime(2026, 9, 21, 14));

    expect((first as Success<PosDailySummaryReport>).value.sent, 1);
    expect((second as Success<PosDailySummaryReport>).value.sent, 0);
    expect(sender.calls, 1);
  });

  test('skips disabled and non-active POS accounts', () async {
    final settings = _Settings({
      SettingKeys.dailyOpsSummaryAutoSend: 'false',
      SettingKeys.posAccounts:
          '[{"posId":"pos-1","customerId":"customer-1","name":"نقطة معلقة","identifiers":["777123456"],"notifyPhone":"777123456","status":"suspended","percentageMode":"defaultCategory"}]',
    });
    final sender = _Sender();
    final service = LocalPosDailySummaryService(
      posRegistry: LocalPosAccountRegistry(settings: settings, clock: FixedClock(DateTime(2026, 9, 21))),
      transactions: _Transactions(const []),
      balances: _Balances(const Money(minorUnits: 0, currencyCode: 'YER')),
      settings: settings,
      auditLogs: _Audits(),
      messageSender: sender,
      clock: FixedClock(DateTime(2026, 9, 21)),
      ids: SequentialIdGenerator(),
    );

    final result = await service.sendDue();
    expect((result as Success<PosDailySummaryReport>).value.sent, 0);
    expect(sender.calls, 0);
  });
}

final class _Settings implements SettingsRepository {
  _Settings(this.values);
  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    if (value == null) return const Success(null);
    return Success(
      AppSetting(
        key: key,
        value: value,
        updatedAt: DateTime(2026, 9, 21),
      ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _Transactions implements TransactionRepository {
  _Transactions(this.rows);
  final List<Transaction> rows;

  @override
  Future<Result<void>> append(Transaction transaction) async {
    rows.add(transaction);
    return const Success(null);
  }

  @override
  Future<Result<Transaction?>> findByReference(String reference) async {
    for (final row in rows) {
      if (row.reference == reference) return Success(row);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Transaction>>> findByCustomer(String customerId) async =>
      Success(rows.where((row) => row.customerId == customerId).toList());

  @override
  Future<Result<List<Transaction>>> listCompleted({
    String? currencyCode,
  }) async {
    return Success(
      rows
          .where(
            (row) =>
                row.status == TransactionStatus.completed &&
                (currencyCode == null ||
                    row.amount.currencyCode == currencyCode),
          )
          .toList(),
    );
  }

  @override
  Future<Result<List<Transaction>>> listRecent({int limit = 50}) async =>
      Success(rows.take(limit).toList());
}

final class _Balances implements CustomerBalanceService {
  _Balances(this.value);
  final Money value;

  @override
  Future<Result<Money>> getBalance({
    required String customerId,
    required String currencyCode,
  }) async =>
      Success(value);

  @override
  Future<Result<Money>> getTotalOutstanding({
    required String currencyCode,
  }) async =>
      Success(value);

  @override
  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
  }) async =>
      Success(
        Transaction(
          id: 'credit',
          type: TransactionType.deposit,
          status: TransactionStatus.completed,
          amount: amount,
          createdAt: DateTime(2026, 9, 21),
          customerId: customerId,
          reference: reference,
        ),
      );
}

final class _Sender implements MessageSender {
  int calls = 0;
  String? lastDestination;
  String? lastBody;

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    calls++;
    lastDestination = destination;
    lastBody = body;
    return const Success(null);
  }
}

final class _Audits implements AuditLogRepository {
  final entries = <AuditLog>[];

  @override
  Future<Result<void>> append(AuditLog log) async {
    entries.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(
    String entityType,
    String entityId,
  ) async =>
      Success(
        entries
            .where(
              (entry) =>
                  entry.entityType == entityType &&
                  entry.entityId == entityId,
            )
            .toList(),
      );
}
