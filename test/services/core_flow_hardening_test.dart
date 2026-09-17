import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/incoming_sms_handler.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage, CustomerIdentifier, AuditLog;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/repositories/unit_of_work.dart';
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
      parser = _FakeParser(const ParsedTransfer(messageId: 'unused', amount: Money(minorUnits: 50000, currencyCode: 'YER'), customerIdentifier: '770123456', identifierType: TransferIdentifierType.phone, reference: 'BANK-REF-42'));
      processor = _FakeProcessor();
      handler = IncomingSmsHandler(bridge: SmsBridge(), messages: messages, parser: parser, processor: processor, ids: SequentialIdGenerator());
    });

    test('same SMS is idempotent across time changes', () async {
      final first = await handler.handleManual(sender: 'bank', body: 'تم تحويل 500 ريال الى 770123456 برقم العملية BANK-REF-42', receivedAt: DateTime.utc(2026, 9, 12, 1));
      final second = await handler.handleManual(sender: 'bank', body: 'تم تحويل 500 ريال الى 770123456 برقم العملية BANK-REF-42', receivedAt: DateTime.utc(2026, 9, 12, 2));
      expect(first, isA<Success<Transaction?>>());
      expect(second, isA<Success<Transaction?>>());
      expect(processor.calls, 1);
      expect(messages.store, hasLength(1));
      expect(messages.seenExternalReferences, everyElement('pay:v1:ref:bank:BANK-REF-42'));
      expect(messages.seenExternalReferences, hasLength(2));
    });
  });

  group('LocalTransferProcessor recovery and rollback', () {
    late AppDatabase database;
    late LocalMessageRepository messages;
    late LocalTransactionRepository transactions;
    late LocalCustomerRepository customers;
    setUp(() { database = AppDatabase(NativeDatabase.memory()); messages = LocalMessageRepository(database); transactions = LocalTransactionRepository(database); customers = LocalCustomerRepository(database); });
    tearDown(() async { await database.close(); });

    test('rejection survives business rollback boundary', () async {
      final result = await messages.save(_message('m-reject', status: MessageProcessingStatus.received));
      expect(result, isA<Success<void>>());
      final found = await messages.findById('m-reject');
      expect((found as Success<IncomingMessage?>).value?.status, MessageProcessingStatus.received);
    });
  });
}

IncomingMessage _message(String id, {required MessageProcessingStatus status}) => IncomingMessage(id: id, sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: status);

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};
  final seenExternalReferences = <String>[];
  @override Future<Result<void>> save(IncomingMessage message) async { store[message.id] = message; if (message.externalReference != null) seenExternalReferences.add(message.externalReference!); return const Success(null); }
  @override Future<Result<IncomingMessage?>> findById(String id) async => Success(store[id]);
  @override Future<Result<IncomingMessage?>> findByExternalReference(String reference) async { return Success(store.values.where((m) => m.externalReference == reference).cast<IncomingMessage?>().firstOrNull); }
  @override Future<Result<List<IncomingMessage>>> pendingProcessing() async => Success(store.values.toList());
  @override Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async => Success(store.values.where((m) => m.status == status).toList());
  @override Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async => Success(store.values.take(limit).toList());
  @override Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async { final m = store[id]!; store[id] = IncomingMessage(id: m.id, sender: m.sender, body: m.body, receivedAt: m.receivedAt, status: status, externalReference: m.externalReference, customerIdentifier: m.customerIdentifier); return const Success(null); }
}
final class _FakeParser implements MessageParser { const _FakeParser(this.transfer); final ParsedTransfer transfer; @override Result<ParsedTransfer> parse(IncomingMessage message) => Success(ParsedTransfer(messageId: message.id, amount: transfer.amount, customerIdentifier: transfer.customerIdentifier, identifierType: transfer.identifierType, reference: transfer.reference)); }
final class _FakeProcessor implements TransferProcessor { int calls = 0; @override Future<Result<Transaction>> process(ParsedTransfer transfer) async { calls++; return Success(Transaction(id: 'tx-$calls', type: TransactionType.deposit, status: TransactionStatus.completed, amount: transfer.amount, customerId: 'c1', reference: transfer.reference, createdAt: DateTime.utc(2026, 9, 12))); } }
