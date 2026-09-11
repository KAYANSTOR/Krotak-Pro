import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/incoming_sms_handler.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/repositories/unit_of_work.dart';
import 'package:net_app/domain/services/local_customer_identity_resolver.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/platform/sms_bridge.dart';

void main() {
  group('IncomingSmsHandler idempotency', () {
    late _FakeMessages messages;
    late _FakeParser parser;
    late _FakeProcessor processor;
    late IncomingSmsHandler handler;

    setUp(() {
      messages = _FakeMessages();
      parser = _FakeParser(
        const ParsedTransfer(
          messageId: 'unused',
          amount: Money(minorUnits: 50000, currencyCode: 'YER'),
          customerIdentifier: '770123456',
          identifierType: TransferIdentifierType.phone,
          reference: 'BANK-REF-42',
        ),
      );
      processor = _FakeProcessor();
      handler = IncomingSmsHandler(
        bridge: SmsBridge(),
        messages: messages,
        parser: parser,
        processor: processor,
        ids: SequentialIdGenerator(),
      );
    });

    test('same SMS is idempotent across time changes', () async {
      final first = await handler.handleManual(
        sender: 'bank',
        body: 'تم تحويل 500 ريال الى 770123456 برقم العملية BANK-REF-42',
        receivedAt: DateTime.utc(2026, 9, 12, 1, 0),
      );
      final second = await handler.handleManual(
        sender: 'bank',
        body: 'تم تحويل 500 ريال الى 770123456 برقم العملية BANK-REF-42',
        receivedAt: DateTime.utc(2026, 9, 12, 2, 0),
      );

      expect(first, isA<Success<Transaction?>>());
      expect(second, isA<Success<Transaction?>>());
      expect(processor.calls, 1);
      expect(messages.store, hasLength(1));
      expect(messages.seenExternalReferences.single, 'sms:v2:ref:bank:BANK-REF-42');
    });
  });

  group('LocalTransferProcessor recovery and rollback', () {
    late AppDatabase database;
    late LocalMessageRepository messages;
    late LocalTransactionRepository transactions;
    late _FailingAudit audit;
    late _SuccessfulResolver resolver;
    late LocalTransferProcessor processor;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      messages = LocalMessageRepository(database);
      transactions = LocalTransactionRepository(database);
      audit = _FailingAudit();
      resolver = _SuccessfulResolver();
      processor = LocalTransferProcessor(
        messages: messages,
        customers: _UnusedCustomers(),
        balances: _DbWritingBalance(transactions),
        auditLogs: audit,
        unitOfWork: _DriftUow(database),
        clock: FixedClock(DateTime.utc(2026, 9, 12, 1)),
        ids: SequentialIdGenerator(),
        identityResolver: resolver,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('rejection survives business rollback boundary', () async {
      await messages.save(_message('m-reject', status: MessageProcessingStatus.received));
      final rejectProcessor = LocalTransferProcessor(
        messages: messages,
        customers: _UnusedCustomers(),
        balances: _DbWritingBalance(transactions),
        auditLogs: _AcceptingAudit(),
        unitOfWork: _DriftUow(database),
        clock: FixedClock(DateTime.utc(2026, 9, 12, 1)),
        ids: SequentialIdGenerator(),
        identityResolver: _UnresolvedResolver(),
      );

      final result = await rejectProcessor.process(_transfer('m-reject'));
      final stored = await messages.findById('m-reject');

      expect(result, isA<Failure<Transaction>>());
      expect((stored as Success<IncomingMessage?>).value!.status,
          MessageProcessingStatus.rejected);
    });

    test('mid-flow audit failure rolls back transaction and leaves failed state for recovery',
        () async {
      await messages.save(_message('m-fail', status: MessageProcessingStatus.parsed));

      final result = await processor.process(_transfer('m-fail'));
      final stored = await messages.findById('m-fail');
      final ledger = await transactions.findByCustomer('customer-1');

      expect(result, isA<Failure<Transaction>>());
      expect((stored as Success<IncomingMessage?>).value!.status,
          MessageProcessingStatus.failed);
      expect((ledger as Success<List<Transaction>>).value, isEmpty);
      expect(audit.attempts, 1);
    });
  });
}

IncomingMessage _message(
  String id, {
  required MessageProcessingStatus status,
}) => IncomingMessage(
      id: id,
      sender: 'bank',
      body: 'body',
      receivedAt: DateTime.utc(2026, 9, 12),
      status: status,
      externalReference: 'sms:v2:ref:bank:$id',
    );

ParsedTransfer _transfer(String messageId) => ParsedTransfer(
      messageId: messageId,
      amount: const Money(minorUnits: 50000, currencyCode: 'YER'),
      customerIdentifier: '770123456',
      identifierType: TransferIdentifierType.phone,
      reference: 'REF-$messageId',
    );

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};
  final seenExternalReferences = <String>[];

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    if (message.externalReference != null &&
        store.values.any((m) => m.externalReference == message.externalReference)) {
      return const Failure(
        AppFailure(code: 'unique_violation', message: 'duplicate'),
      );
    }
    store[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async => Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async {
    seenExternalReferences.add(reference);
    for (final message in store.values) {
      if (message.externalReference == reference) return Success(message);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async =>
      Success(store.values.where((m) => m.status != MessageProcessingStatus.processed).toList());

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async =>
      Success(store.values.where((m) => m.status == status).toList());

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(store.values.take(limit).toList());

  @override
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async {
    final current = store[id];
    if (current == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'missing'));
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

final class _FakeParser implements MessageParser {
  const _FakeParser(this.transfer);
  final ParsedTransfer transfer;

  @override
  Result<ParsedTransfer> parse(IncomingMessage message) => Success(
        ParsedTransfer(
          messageId: message.id,
          amount: transfer.amount,
          customerIdentifier: transfer.customerIdentifier,
          identifierType: transfer.identifierType,
          reference: transfer.reference,
        ),
      );
}

final class _FakeProcessor implements TransferProcessor {
  int calls = 0;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    calls++;
    return Success(
      Transaction(
        id: 'tx-$calls',
        customerId: 'customer-1',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: transfer.amount,
        createdAt: DateTime.utc(2026, 9, 12),
        reference: transfer.reference,
      ),
    );
  }
}

final class _UnresolvedResolver extends LocalCustomerIdentityResolver {
  const _UnresolvedResolver() : super(customers: _UnusedCustomers());

  @override
  Future<Result<CustomerIdentityResolution>> resolve({
    required String identifierValue,
    required TransferIdentifierType identifierType,
  }) async =>
      const Success(
        CustomerIdentityResolution.unresolved(
          reasonCode: 'customer_not_found',
          reasonMessage: 'missing',
        ),
      );
}

final class _SuccessfulResolver extends LocalCustomerIdentityResolver {
  const _SuccessfulResolver() : super(customers: _UnusedCustomers());

  @override
  Future<Result<CustomerIdentityResolution>> resolve({
    required String identifierValue,
    required TransferIdentifierType identifierType,
  }) async =>
      Success(
        CustomerIdentityResolution.resolved(
          customer: Customer(
            id: 'customer-1',
            displayName: 'Customer',
            status: CustomerStatus.active,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          deliveryPhone: identifierValue,
          matchedIdentifier: null,
        ),
      );
}

final class _UnusedCustomers implements CustomerRepository {
  const _UnusedCustomers();

  @override
  Future<Result<Customer?>> findById(String id) async => const Success(null);

  @override
  Future<Result<Customer?>> findByIdentifier(String value) async => const Success(null);

  @override
  Future<Result<List<Customer>>> search(String query) async => const Success([]);

  @override
  Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId) async =>
      const Success([]);

  @override
  Future<Result<void>> save(Customer customer) async => const Success(null);

  @override
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier) async =>
      const Success(null);
}

final class _DbWritingBalance implements CustomerBalanceService {
  _DbWritingBalance(this.transactions);
  final LocalTransactionRepository transactions;

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
      id: 'tx-mid-flow',
      customerId: customerId,
      type: TransactionType.deposit,
      status: TransactionStatus.completed,
      amount: amount,
      createdAt: DateTime.utc(2026, 9, 12),
      reference: reference,
    );
    final appended = await transactions.append(tx);
    if (appended is Failure<void>) return Failure(appended.error);
    return Success(tx);
  }
}

final class _AcceptingAudit implements AuditLogRepository {
  @override
  Future<Result<void>> append(AuditLog log) async => const Success(null);

  @override
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async =>
      const Success([]);
}

final class _FailingAudit implements AuditLogRepository {
  int attempts = 0;

  @override
  Future<Result<void>> append(AuditLog log) async {
    attempts++;
    return const Failure(
      AppFailure(code: 'audit_failed', message: 'audit failed'),
    );
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async =>
      const Success([]);
}

final class _DriftUow implements UnitOfWork {
  const _DriftUow(this.database);
  final AppDatabase database;

  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) async {
    try {
      return await database.transaction(() async {
        final result = await action();
        if (result is Failure<T>) throw _Rollback(result.error);
        return result;
      });
    } on _Rollback catch (error) {
      return Failure(error.failure);
    } catch (error) {
      return Failure(
        AppFailure(code: 'transaction_failed', message: error.toString()),
      );
    }
  }
}

final class _Rollback implements Exception {
  const _Rollback(this.failure);
  final AppFailure failure;
}
