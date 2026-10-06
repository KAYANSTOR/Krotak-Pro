import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide
        AppSetting,
        AuditLog,
        Card,
        CardCategory,
        Customer,
        IncomingMessage,
        Sale,
        Transaction;
import 'package:net_app/domain/entities/advance.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';

/// سلفني: تخصيص الإيداعات ذريًا + idempotency بالمرجع + إيجاد السلفة مباشرة
/// (بلا الاعتماد على «آخر 1000 حركة»). كل شيء هنا على قاعدة Drift الحقيقية
/// وحاوية التطبيق الفعلية، لا بدائل.
void main() {
  const currency = 'YER';

  late AppDatabase database;
  late AppContainer container;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-salafni-settlement'),
    );
    await container.settings.save(
      AppSetting(
        key: SettingKeys.salafniEnabled,
        value: 'true',
        updatedAt: container.clock.now(),
      ),
    );
  });

  tearDown(() async {
    await container.dispose();
    await database.close();
  });

  Future<Customer> createCustomer(String value) async {
    final created = await container.customerService.create(
      displayName: 'عميل $value',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: value,
    );
    return (created as Success<Customer>).value;
  }

  Future<void> seedAdvance({
    required String id,
    required String customerId,
    required DateTime createdAt,
    required int amountMinor,
    String cardId = '',
  }) async {
    final card = cardId.isEmpty ? 'card-$id' : cardId;
    final amount = Money(minorUnits: amountMinor, currencyCode: currency);
    await container.transactions.append(
      Transaction(
        id: id,
        type: TransactionType.advance,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: createdAt,
        customerId: customerId,
        reference: 'salafni:$id',
      ),
    );
    await container.sales.save(
      Sale(
        id: id,
        customerId: customerId,
        cardId: card,
        amount: amount,
        status: TransactionStatus.completed,
        createdAt: createdAt,
      ),
    );
  }

  Future<List<Transaction>> depositsOf(String customerId) async {
    final rows = await container.transactions.findByCustomer(customerId);
    return (rows as Success<List<Transaction>>)
        .value
        .where((row) => row.type == TransactionType.deposit)
        .toList(growable: false);
  }

  test(
      'replaying the same settlement reference credits the advance exactly once',
      () async {
    final customer = await createCustomer('733111001');
    final now = container.clock.now();
    await seedAdvance(
      id: 'adv-once',
      customerId: customer.id,
      createdAt: now.subtract(const Duration(hours: 2)),
      amountMinor: 10000,
    );

    final first = await container.advanceService.applyPayment(
      customerId: customer.id,
      amount: const Money(minorUnits: 10000, currencyCode: currency),
      reference: 'ref-once',
    );
    expect(first, isA<Success<AdvancePaymentResult>>());
    final firstValue = (first as Success<AdvancePaymentResult>).value;
    expect(firstValue.applied.minorUnits, 10000);
    expect(firstValue.remaining.minorUnits, 0);
    expect(firstValue.settlementTransaction, isNotNull);
    expect(await depositsOf(customer.id), hasLength(1));

    final replay = await container.advanceService.applyPayment(
      customerId: customer.id,
      amount: const Money(minorUnits: 10000, currencyCode: currency),
      reference: 'ref-once',
    );
    expect(replay, isA<Success<AdvancePaymentResult>>());
    final replayValue = (replay as Success<AdvancePaymentResult>).value;
    expect(replayValue.applied.minorUnits, 10000,
        reason: 'إعادة نفس المرجع لا تخصم مرتين');
    expect(replayValue.remaining.minorUnits, 0);
    expect(
      await depositsOf(customer.id),
      hasLength(1),
      reason: 'لا حركة إيداع ثانية لنفس المرجع',
    );

    final advances =
        await container.advanceService.listCustomerAdvances(customer.id);
    final only = (advances as Success<List<Advance>>).value.single;
    expect(only.status, AdvanceStatus.settled);
    expect(only.outstanding.minorUnits, 0);
  });

  test('a settlement that fails midway leaves no partially credited deposits',
      () async {
    final customer = await createCustomer('733111002');
    final now = container.clock.now();
    await seedAdvance(
      id: 'adv-old',
      customerId: customer.id,
      createdAt: now.subtract(const Duration(days: 2)),
      amountMinor: 10000,
    );
    await seedAdvance(
      id: 'adv-new',
      customerId: customer.id,
      createdAt: now.subtract(const Duration(days: 1)),
      amountMinor: 10000,
    );
    // دفعة سابقة فعلية على السلفة الأقدم بالمرجع نفسه: الحركة التالية لها
    // بنفس المرجع ستُرفض (فهرس فريد)، فتجب أن تتراجع المعاملة كلها.
    await container.transactions.append(
      Transaction(
        id: 'txn-prior',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 1, currencyCode: currency),
        createdAt: now.subtract(const Duration(hours: 5)),
        customerId: customer.id,
        reference: 'salafni-settlement:ref-atomic:adv-old',
        relatedTransactionId: 'adv-old',
      ),
    );

    final result = await container.advanceService.applyPayment(
      customerId: customer.id,
      amount: const Money(minorUnits: 15000, currencyCode: currency),
      reference: 'ref-atomic',
    );
    expect(result, isA<Failure<AdvancePaymentResult>>());

    final deposits = await depositsOf(customer.id);
    expect(deposits, hasLength(1),
        reason: 'لا يُكتب جزء من الدفعة ثم يتعثر الباقي');
    expect(deposits.single.id, 'txn-prior');

    final advances =
        await container.advanceService.listCustomerAdvances(customer.id);
    final byId = {
      for (final advance in (advances as Success<List<Advance>>).value)
        advance.id: advance,
    };
    expect(byId['adv-new']!.outstanding.minorUnits, 10000,
        reason: 'تراجعت حركة السلفة الأحدث');
    expect(byId['adv-new']!.status, AdvanceStatus.open);
    expect(byId['adv-old']!.outstanding.minorUnits, 9999);
  });

  test(
      'an advance stays discoverable once the ledger grows past the recent window',
      () async {
    final customer = await createCustomer('733111003');
    final now = container.clock.now();
    await seedAdvance(
      id: 'adv-window',
      customerId: customer.id,
      createdAt: now.subtract(const Duration(days: 30)),
      amountMinor: 10000,
    );
    await container.cards.save(
      const Card(
        id: 'card-adv-window',
        categoryId: 'cat-adv',
        serialNumber: 'SN-ADV-WINDOW',
        secretCode: 'CODE-ADV-WINDOW',
        status: CardStatus.sold,
      ),
    );
    for (var i = 0; i < 1100; i++) {
      await container.transactions.append(
        Transaction(
          id: 'filler-$i',
          type: TransactionType.deposit,
          status: TransactionStatus.completed,
          amount: const Money(minorUnits: 1, currencyCode: currency),
          createdAt: now.subtract(Duration(minutes: 1100 - i)),
          customerId: customer.id,
        ),
      );
    }

    final issue = await container.advanceService.request(
      customerId: customer.id,
      currencyCode: currency,
      operationId: 'adv-window',
    );
    expect(issue, isA<Success<AdvanceIssue>>());
    expect(
      (issue as Success<AdvanceIssue>).value.advance.id,
      'adv-window',
      reason: 'نفس العملية لا تُصدر سلفة ثانية',
    );

    final advances =
        await container.advanceService.listCustomerAdvances(customer.id);
    expect((advances as Success<List<Advance>>).value, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
