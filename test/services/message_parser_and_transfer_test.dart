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
    ];
    final parser = LocalMessageParser(templates: templates);

    test('parses a matching SMS body', () {
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
      expect(parsed.amount.minorUnits, 150000); // 1500.00 * 100
      expect(parsed.customerIdentifier, '770123456');
      expect(parsed.reference, 'REF-99');
      expect(parsed.messageId, 'm1');
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
      expect((result as Failure<ParsedTransfer>).error.code, 'message_not_matched');
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
      expect((result as Failure).error.code, 'no_active_template');
    });
  });

  group('LocalTransferProcessor', () {
    late _FakeMessages messages;
    late _FakeCustomers customers;
    late _FakeBalances balances;
    late _FakeAudit audit;
    late LocalTransferProcessor processor;
    late FixedClock clock;

    setUp(() {
      messages = _FakeMessages();
      customers = _FakeCustomers();
      balances = _FakeBalances();
      audit = _FakeAudit();
      clock = FixedClock(DateTime.utc(2026, 9, 11));
      processor = LocalTransferProcessor(
        messages: messages,
        customers: customers,
        balances: balances,
        auditLogs: audit,
        unitOfWork: const _PassthroughUnitOfWork(),
        clock: clock,
        ids: SequentialIdGenerator(),
      );
    });

    test('credits customer and marks message processed', () async {
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
        reference: 'REF-1',
      );

      final result = await processor.process(transfer);
      expect(result, isA<Success<Transaction>>());
      expect(messages.store['m1']!.status, MessageProcessingStatus.processed);
      expect(balances.credits.length, 1);
      expect(audit.logs.length, 1);
    });

    test('rejects when customer missing', () async {
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
        customerIdentifier: 'unknown',
        reference: 'REF-2',
      );

      final result = await processor.process(transfer);
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure).error.code, 'customer_not_found');
      expect(messages.store['m2']!.status, MessageProcessingStatus.rejected);
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
        reference: 'REF-3',
      );

      final result = await processor.process(transfer);
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure).error.code, 'message_already_processed');
    });
  });
}

// --- fakes ---

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
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async =>
      const Success(null);

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async =>
      const Success([]);


  @override
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async =>
      Success(store.values.where((m) => m.status == status).toList(growable: false));

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
}

final class _FakeCustomers implements CustomerRepository {
  final byId = <String, Customer>{};

  @override
  Future<Result<Customer?>> findById(String id) async => const Success(null);

  @override
  Future<Result<Customer?>> findByIdentifier(String value) async =>
      Success(byId[value]);

  @override
  Future<Result<List<Customer>>> search(String query) async =>
      const Success([]);

  @override
  Future<Result<List<CustomerIdentifier>>> listIdentifiers(
    String customerId,
  ) async =>
      const Success([]);

  @override
  Future<Result<void>> save(Customer customer) async => const Success(null);

  @override
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier) async =>
      const Success(null);
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
  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
  }) async {
    final tx = Transaction(
      id: 'tx-${credits.length + 1}',
      customerId: customerId,
      type: TransactionType.deposit,
      status: TransactionStatus.completed,
      amount: amount,
      reference: reference,
      createdAt: DateTime.utc(2026, 9, 11),
    );
    credits.add(tx);
    return Success(tx);
  }
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
      Success(logs.where((l) => l.entityType == entityType && l.entityId == entityId).toList());
}
