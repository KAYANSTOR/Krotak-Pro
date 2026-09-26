import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/repositories/unit_of_work.dart';
import 'package:net_app/domain/services/local_customer_identity_resolver.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  group('LocalMessageParser', () {
    final templates = [
      const TransferTemplate(
        id: 't1',
        name: 'Yemen transfer',
        pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
        isActive: true,
      ),
      const TransferTemplate(
        id: 't-account',
        name: 'Account style percent',
        pattern: 'ايداع %amount لحساب %account المرجع %ref',
        isActive: true,
      ),
    ];
    final parser = LocalMessageParser(templates: templates);

    test('parses a matching SMS body with phone type', () {
      final message = IncomingMessage(
        id: 'm1',
        sender: '777',
        body: 'تم تحويل 1500 ريال الى 770123456 برقم العملية REF-99',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: MessageProcessingStatus.received,
      );

      final result = parser.parse(message);
      expect(result, isA<Success<ParsedTransfer>>());
      final parsed = (result as Success<ParsedTransfer>).value;
      expect(parsed.amount.minorUnits, 150000);
      expect(parsed.customerIdentifier, '770123456');
      expect(parsed.identifierType, TransferIdentifierType.phone);
      expect(parsed.reference, 'REF-99');
      expect(parsed.messageId, 'm1');
      expect(parsed.templateId, 't1');
    });

    test('parses %account style and classifies as account', () {
      final message = IncomingMessage(
        id: 'm-acc',
        sender: 'bank',
        body: 'ايداع 200 لحساب 120025 المرجع OP-88',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: MessageProcessingStatus.received,
      );

      final result = parser.parse(message);
      expect(result, isA<Success<ParsedTransfer>>());
      final parsed = (result as Success<ParsedTransfer>).value;
      expect(parsed.amount.minorUnits, 20000);
      expect(parsed.customerIdentifier, '120025');
      expect(parsed.identifierType, TransferIdentifierType.account);
      expect(parsed.reference, 'OP-88');
    });

    test('normalizes Arabic-Indic digits in amount and phone', () {
      final message = IncomingMessage(
        id: 'm-ar',
        sender: '777',
        body: 'تم تحويل ١٥٠٠ ريال الى ٧٧٠١٢٣٤٥٦ برقم العملية REF-AR',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: MessageProcessingStatus.received,
      );

      final result = parser.parse(message);
      expect(result, isA<Success<ParsedTransfer>>());
      final parsed = (result as Success<ParsedTransfer>).value;
      expect(parsed.amount.minorUnits, 150000);
      expect(parsed.customerIdentifier, '770123456');
      expect(parsed.identifierType, TransferIdentifierType.phone);
    });

    test('fails when body does not match', () {
      final message = IncomingMessage(
        id: 'm2',
        sender: '777',
        body: 'رسالة غير معروفة',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: MessageProcessingStatus.received,
      );

      final result = parser.parse(message);
      expect(result, isA<Failure<ParsedTransfer>>());
      expect(
        (result as Failure<ParsedTransfer>).error.code,
        'message_not_matched',
      );
    });

    test('fails when no active templates', () {
      final emptyParser = LocalMessageParser(templates: const []);
      final message = IncomingMessage(
        id: 'm3',
        sender: '777',
        body: 'تم تحويل 10 ريال الى 770000000 برقم العملية X',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: MessageProcessingStatus.received,
      );

      final result = emptyParser.parse(message);
      expect(result, isA<Failure<ParsedTransfer>>());
      expect(
        (result as Failure<ParsedTransfer>).error.code,
        'no_active_template',
      );
    });

    test('rejects a financial template match without an explicit reference', () {
      final noRefParser = LocalMessageParser(
        templates: [
          const TransferTemplate(
            id: 't-no-ref',
            name: 'No reference',
            pattern: 'تم تحويل {amount} ريال الى {phone}',
            isActive: true,
          ),
        ],
      );
      final result = noRefParser.parse(
        IncomingMessage(
          id: 'm-no-ref',
          sender: 'bank',
          body: 'تم تحويل 500 ريال الى 770123456',
          receivedAt: DateTime.utc(2026, 9, 12),
          status: MessageProcessingStatus.received,
        ),
      );

      expect(result, isA<Failure<ParsedTransfer>>());
      expect(
        (result as Failure<ParsedTransfer>).error.code,
        'message_not_matched',
      );
    });
  });

  group('LocalCustomerIdentityResolver', () {
    test('resolves phone and exposes delivery phone', () async {
      final customers = _FakeCustomers();
      customers.byId['770123456'] = Customer(
        id: 'c1',
        displayName: 'Ali',
        status: CustomerStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      customers.identifiers['c1'] = [
        const CustomerIdentifier(
          id: 'id1',
          customerId: 'c1',
          type: CustomerIdentifierType.phoneNumber,
          value: '770123456',
          isPrimary: true,
        ),
      ];
      final resolver = LocalCustomerIdentityResolver(customers: customers);
      final result = await resolver.resolve(
        identifierValue: '770123456',
        identifierType: TransferIdentifierType.phone,
      );
      expect(result, isA<Success<CustomerIdentityResolution>>());
      final r = (result as Success<CustomerIdentityResolution>).value;
      expect(r.isResolved, isTrue);
      expect(r.customer!.id, 'c1');
      expect(r.deliveryPhone, '770123456');
    });

    test('account maps to customer without treating account as delivery phone',
        () async {
      final customers = _FakeCustomers();
      customers.byId['120025'] = Customer(
        id: 'c2',
        displayName: 'Shop',
        status: CustomerStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      customers.identifiers['c2'] = [
        const CustomerIdentifier(
          id: 'id-acc',
          customerId: 'c2',
          type: CustomerIdentifierType.externalReference,
          value: '120025',
          isPrimary: false,
        ),
        const CustomerIdentifier(
          id: 'id-ph',
          customerId: 'c2',
          type: CustomerIdentifierType.phoneNumber,
          value: '770999888',
          isPrimary: true,
        ),
      ];
      final resolver = LocalCustomerIdentityResolver(customers: customers);
      final result = await resolver.resolve(
        identifierValue: '120025',
        identifierType: TransferIdentifierType.account,
      );
      final r = (result as Success<CustomerIdentityResolution>).value;
      expect(r.isResolved, isTrue);
      expect(r.deliveryPhone, '770999888');
      expect(r.deliveryPhone, isNot('120025'));
    });

    test('unresolved when no mapping', () async {
      final resolver =
          LocalCustomerIdentityResolver(customers: _FakeCustomers());
      final result = await resolver.resolve(
        identifierValue: 'missing',
        identifierType: TransferIdentifierType.account,
      );
      final r = (result as Success<CustomerIdentityResolution>).value;
      expect(r.isResolved, isFalse);
      expect(r.reasonCode, 'customer_not_found');
    });
  });

  group('LocalTransferProcessor', () {
    late _FakeMessages messages;
    late _FakeCustomers customers;
    late _FakeBalances balances;
    late _FakeAudit audit;
    late LocalTransferProcessor processor;

    setUp(() {
      messages = _FakeMessages();
      customers = _FakeCustomers();
      balances = _FakeBalances();
      audit = _FakeAudit();
      processor = LocalTransferProcessor(
        messages: messages,
        customers: customers,
        balances: balances,
        auditLogs: audit,
        unitOfWork: const _PassthroughUnitOfWork(),
        clock: FixedClock(DateTime.utc(2026, 9, 11)),
        ids: SequentialIdGenerator(),
      );
    });

    test('credits active customer and marks processed', () async {
      messages.store['m1'] = IncomingMessage(
        id: 'm1',
        sender: 'bank',
        body: 'body',
        receivedAt: DateTime.utc(2026, 9, 11),
        status: MessageProcessingStatus.received,
      );
      customers.byId['770123456'] = Customer(
        id: 'c1',
        displayName: 'Ali',
        status: CustomerStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final transfer = ParsedTransfer(
        messageId: 'm1',
        amount: const Money(minorUnits: 50000, currencyCode: 'YER'),
        customerIdentifier: '770123456',
        identifierType: TransferIdentifierType.phone,
        reference: 'REF-1',
      );

      final result = await processor.process(transfer);
      expect(result, isA<Success<Transaction>>());
      expect(messages.store['m1']!.status, MessageProcessingStatus.processed);
      expect(balances.credits.length, 1);
      expect(audit.logs.any((l) => l.action == 'transfer_processed'), isTrue);
    });

    test('rejects phone customer when CustomerService absent (no auto-provision)', () async {
      messages.store['m2'] = IncomingMessage(
        id: 'm2',
        sender: 'bank',
        body: 'body',
        receivedAt: DateTime.utc(2026, 9, 11),
        status: MessageProcessingStatus.received,
      );

      final transfer = ParsedTransfer(
        messageId: 'm2',
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        customerIdentifier: '770123456',
        identifierType: TransferIdentifierType.phone,
        reference: 'REF-2',
      );

      // processor created without customerService → still rejects
      final result = await processor.process(transfer);
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure).error.code, 'customer_not_found');
      expect(messages.store['m2']!.status, MessageProcessingStatus.rejected);
      expect(audit.logs.any((l) => l.action == 'transfer_unresolved'), isTrue);
    });

    test('auto-provisions unknown phone customer and credits', () async {
      messages.store['m2b'] = IncomingMessage(
        id: 'm2b',
        sender: 'JAIB',
        body: 'body',
        receivedAt: DateTime.utc(2026, 9, 11),
        status: MessageProcessingStatus.received,
      );

      final clock = FixedClock(DateTime.utc(2026, 9, 11));
      final ids = SequentialIdGenerator();
      final withProvision = LocalTransferProcessor(
        messages: messages,
        customers: customers,
        balances: balances,
        auditLogs: audit,
        unitOfWork: const _PassthroughUnitOfWork(),
        clock: clock,
        ids: ids,
        customerService: _FakeCustomerService(customers, ids, clock),
      );

      final transfer = ParsedTransfer(
        messageId: 'm2b',
        amount: const Money(minorUnits: 25000, currencyCode: 'YER'),
        customerIdentifier: '777999888',
        identifierType: TransferIdentifierType.phone,
        reference: 'REF-AUTO',
      );

      final result = await withProvision.process(transfer);
      expect(result, isA<Success<Transaction>>());
      expect(messages.store['m2b']!.status, MessageProcessingStatus.processed);
      expect(balances.credits.length, greaterThanOrEqualTo(1));
      expect(audit.logs.any((l) => l.action == 'ledger_account_auto_provisioned'), isTrue);
      expect(audit.logs.any((l) => l.action == 'transfer_processed'), isTrue);
      // customer was created
      final found = await customers.findByIdentifier('777999888');
      expect((found as Success).value, isNotNull);
    });

    test('rejects account identifier when customer missing (no auto-provision)', () async {
      messages.store['m2c'] = IncomingMessage(
        id: 'm2c',
        sender: 'bank',
        body: 'body',
        receivedAt: DateTime.utc(2026, 9, 11),
        status: MessageProcessingStatus.received,
      );

      final clock = FixedClock(DateTime.utc(2026, 9, 11));
      final ids = SequentialIdGenerator();
      final withProvision = LocalTransferProcessor(
        messages: messages,
        customers: customers,
        balances: balances,
        auditLogs: audit,
        unitOfWork: const _PassthroughUnitOfWork(),
        clock: clock,
        ids: ids,
        customerService: _FakeCustomerService(customers, ids, clock),
      );

      final transfer = ParsedTransfer(
        messageId: 'm2c',
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        customerIdentifier: 'ACC-9988',
        identifierType: TransferIdentifierType.account,
        reference: 'REF-ACC',
      );

      final result = await withProvision.process(transfer);
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure).error.code, 'customer_not_found');
      expect(messages.store['m2c']!.status, MessageProcessingStatus.rejected);
      expect(audit.logs.any((l) => l.action == 'transfer_unresolved'), isTrue);
    });

    test('fails when already processed', () async {
      messages.store['m3'] = IncomingMessage(
        id: 'm3',
        sender: 'bank',
        body: 'body',
        receivedAt: DateTime.utc(2026, 9, 11),
        status: MessageProcessingStatus.processed,
      );

      final transfer = ParsedTransfer(
        messageId: 'm3',
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        customerIdentifier: '770123456',
        identifierType: TransferIdentifierType.phone,
        reference: 'REF-3',
      );

      final result = await processor.process(transfer);
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure).error.code, 'message_already_processed');
    });
  });
}


final class _FakeCustomerService implements CustomerService {
  _FakeCustomerService(this.customers, this.ids, this.clock);
  final _FakeCustomers customers;
  final IdGenerator ids;
  final Clock clock;

  @override
  Future<Result<Customer>> create({
    required String displayName,
    required CustomerIdentifierType identifierType,
    required String identifierValue,
    CustomerStatus status = CustomerStatus.active,
  }) async {
    final existing = await customers.findByIdentifier(identifierValue.trim());
    if (existing is Success<Customer?> && existing.value != null) {
      return const Failure(AppFailure(code: 'duplicate_identifier', message: 'Identifier already exists'));
    }
    final now = clock.now();
    final customer = Customer(
      id: ids.next('customer'),
      displayName: displayName,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    await customers.save(customer);
    await customers.saveIdentifier(CustomerIdentifier(
      id: ids.next('identifier'),
      customerId: customer.id,
      type: identifierType,
      value: identifierValue.trim(),
      isPrimary: true,
    ));
    return Success(customer);
  }

  @override
  Future<Result<Customer>> promoteToActive(String customerId) async {
    final existing = await customers.findById(customerId);
    if (existing is Failure<Customer?>) return Failure(existing.error);
    final customer = (existing as Success<Customer?>).value;
    if (customer == null) {
      return const Failure(AppFailure(code: 'customer_not_found', message: 'Customer was not found'));
    }
    final updated = customer.copyWith(status: CustomerStatus.active, updatedAt: clock.now());
    final saved = await customers.save(updated);
    if (saved is Failure<void>) return Failure(saved.error);
    return Success(updated);
  }

  @override
  Future<Result<void>> blacklist(String customerId) async => const Success(null);

  @override
  Future<Result<void>> addIdentifier({
    required String customerId,
    required CustomerIdentifierType type,
    required String value,
    required bool isPrimary,
  }) async => const Success(null);

  @override
  Future<Result<void>> bindPrimaryGsm({
    required String customerId,
    required String phone,
  }) async => const Success(null);
}

final class _PassthroughUnitOfWork implements UnitOfWork {
  const _PassthroughUnitOfWork();
  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    store[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(
    String reference,
  ) async =>
      const Success(null);

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async =>
      const Success([]);

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async =>
      Success(
        store.values.where((m) => m.status == status).toList(growable: false),
      );

  @override

  Future<Result<int>> countByStatus(MessageProcessingStatus status) async =>

      Success(store.values.where((m) => m.status == status).length);

  @override
  Stream<int> watchCountByStatus(MessageProcessingStatus status) async* {
    yield store.values.where((m) => m.status == status).length;
  }


  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(store.values.take(limit).toList(growable: false));

  @override
  Future<Result<void>> updateStatus(
    String id,
    MessageProcessingStatus status,
  ) async {
    final current = store[id];
    if (current == null) {
      return const Failure(
        AppFailure(code: 'not_found', message: 'missing'),
      );
    }
    store[id] = IncomingMessage(
      id: current.id,
      sender: current.sender,
      body: current.body,
      receivedAt: current.receivedAt,
      status: status,
      externalReference: current.externalReference,
      customerIdentifier: current.customerIdentifier,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    store.remove(id);
    return const Success(null);
  }
}

final class _FakeCustomers implements CustomerRepository {
  final byId = <String, Customer>{};
  final identifiers = <String, List<CustomerIdentifier>>{};

  @override
  Future<Result<List<CustomerAccountSnapshot>>> listAccountSnapshots({
    String query = '',
    String currencyCode = 'YER',
    int? limit,
    int offset = 0,
  }) async =>
      const Success(<CustomerAccountSnapshot>[]);

  @override
  Future<Result<Customer?>> findById(String id) async => Success(byId[id]);

  @override
  Future<Result<Customer?>> findByIdentifier(String value) async =>
      Success(byId[value]);

  @override
  Future<Result<List<Customer>>> search(String query) async =>
      const Success([]);

  @override
  Future<Result<List<CustomerPhoneSuggestion>>> suggestPhonesByPrefix(
    String prefix, {
    int limit = 8,
  }) async => const Success([]);

  @override
  Future<Result<List<CustomerIdentifier>>> listIdentifiers(
    String customerId,
  ) async =>
      Success(identifiers[customerId] ?? const []);

  @override
  Future<Result<void>> save(Customer customer) async {
    byId[customer.id] = customer;
    return const Success(null);
  }

  @override
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier) async {
    identifiers.putIfAbsent(identifier.customerId, () => []).add(identifier);
    // Also index by value for findByIdentifier
    byId[identifier.value] = byId[identifier.customerId]!;
    return const Success(null);
  }
}

final class _FakeBalances implements CustomerBalanceService {
  final credits = <Transaction>[];

  @override
  Future<Result<Money>> getBalance({
    required String customerId,
    required String currencyCode,
  }) async =>
      Success(Money(minorUnits: 0, currencyCode: currencyCode));

  @override
  Future<Result<Money>> getTotalOutstanding({required String currencyCode}) async =>
      Success(Money(minorUnits: 0, currencyCode: currencyCode));

  @override
  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
    String? reason,
  }) async {
    final tx = Transaction(
      id: 'tx-${credits.length + 1}',
      customerId: customerId,
      type: TransactionType.deposit,
      status: TransactionStatus.completed,
      amount: amount,
      createdAt: DateTime.utc(2026, 9, 11),
      reference: reference,
    );
    credits.add(tx);
    return Success(tx);
  }

  @override
  Future<Result<Transaction>> debit({required String customerId, required Money amount, String? reference, String? reason}) async =>
      Success(Transaction(id: 'debit', customerId: customerId, type: TransactionType.withdrawal, status: TransactionStatus.completed, amount: amount, createdAt: DateTime.utc(2026, 1, 1), reference: reference));
  @override
  Future<Result<CustomerAccountSummary>> getAccountSummary({required String customerId, required String currencyCode}) async =>
      Success(CustomerAccountSummary(balance: Money(minorUnits: 0, currencyCode: currencyCode), totalSalesMinor: 0, totalDepositsMinor: 0, totalWithdrawalsMinor: 0, totalSettlementsMinor: 0, openAdvancesCount: 0, openAdvancesMinor: 0, transactionCount: 0));

}

final class _FakeAudit implements AuditLogRepository {
  final logs = <AuditLog>[];

  @override
  Future<Result<void>> append(AuditLog log) async {
    logs.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(
    String entityType,
    String entityId,
  ) async =>
      const Success([]);
}
