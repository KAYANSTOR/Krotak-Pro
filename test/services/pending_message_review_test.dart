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
import 'package:net_app/domain/rejection_codes.dart';
import 'package:net_app/domain/services/pending_message_review_service.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/trusted_payment_source.dart';

void main() {
  group('PendingMessageReviewService', () {
    late _FakeMessages messages;
    late _FakeBalances balances;
    late _FakeCustomers customers;
    late _FakeCustomerService customerService;
    late _FakeAudit audit;
    late PendingMessageReviewService service;

    setUp(() {
      messages = _FakeMessages();
      balances = _FakeBalances();
      customers = _FakeCustomers();
      customerService = _FakeCustomerService(customers);
      audit = _FakeAudit();
      service = PendingMessageReviewService(
        messages: messages,
        parser: _FakeParser(const ParsedTransfer(messageId: 'm1', amount: Money(minorUnits: 15000, currencyCode: 'YER'), customerIdentifier: '770123456', identifierType: TransferIdentifierType.phone, reference: 'REF-P1')),
        customers: customers,
        customerService: customerService,
        balances: balances,
        auditLogs: audit,
        unitOfWork: const _PassthroughUow(),
        clock: const _FixedClock(),
        ids: SequentialIdGenerator(),
        sourceGuard: trustedPaymentSourceGuard(),
      );
    });

    test('approve credits existing customer and marks processed', () async {
      customers.store['c1'] = Customer(id: 'c1', displayName: 'عميل', status: CustomerStatus.active, createdAt: DateTime.utc(2026, 1, 1), updatedAt: DateTime.utc(2026, 1, 1));
      customers.byIdentifier['770123456'] = 'c1';
      messages.store['m1'] = IncomingMessage(id: 'm1', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.parsed);
      final result = await service.approve('m1');
      expect(result, isA<Success<Transaction>>());
      expect(messages.store['m1']!.status, MessageProcessingStatus.processed);
      expect(balances.credits, 1);
      expect(audit.logs.any((l) => l.action == 'pending_message_approved'), isTrue);
    });

    test('listPending surfaces pending-status messages too', () async {
      messages.store['p1'] = IncomingMessage(id: 'p1', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.pending);
      messages.store['p2'] = IncomingMessage(id: 'p2', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 11), status: MessageProcessingStatus.parsed);

      final result = await service.listPending();

      expect(result, isA<Success<List<IncomingMessage>>>());
      final ids = (result as Success<List<IncomingMessage>>)
          .value
          .map((m) => m.id)
          .toList();
      expect(ids, containsAll(<String>['p1', 'p2']));
    });

    test('reject marks rejected and audits', () async {
      messages.store['m2'] = IncomingMessage(id: 'm2', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.parsed);
      final result = await service.reject('m2', reason: 'اختبار');
      expect(result, isA<Success<void>>());
      expect(messages.store['m2']!.status, MessageProcessingStatus.rejected);
      expect(audit.logs.any((l) => l.action == 'pending_message_rejected'), isTrue);
    });

    test('approve creates customer when missing', () async {
      messages.store['m3'] = IncomingMessage(id: 'm3', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.parsed);
      final result = await service.approve('m3');
      expect(result, isA<Success<Transaction>>());
      expect(customerService.created, 1);
      expect(messages.store['m3']!.status, MessageProcessingStatus.processed);
    });

    // إعادة المحاولة: رسالة سبق رفضها (مثلاً بسبب قالب/محفظة كانت معطّلة
    // وقتها) تتحوّل إلى معتمدة الآن أن أصبح المصدر والقالب سليمين، دون
    // انتظار رسالة جديدة من العميل.
    test('retryRejected approves a previously-rejected message once retried', () async {
      customers.store['c1'] = Customer(id: 'c1', displayName: 'عميل', status: CustomerStatus.active, createdAt: DateTime.utc(2026, 1, 1), updatedAt: DateTime.utc(2026, 1, 1));
      customers.byIdentifier['770123456'] = 'c1';
      messages.store['m1'] = IncomingMessage(id: 'm1', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.rejected);

      final result = await service.retryRejected('m1');

      expect(result, isA<Success<Transaction>>());
      expect(messages.store['m1']!.status, MessageProcessingStatus.processed);
      expect(balances.credits, 1);
      expect(audit.logs.any((l) => l.action == 'message_retried_manually'), isTrue);
    });

    test('retryRejected refuses a message that is not currently rejected', () async {
      messages.store['m1'] = IncomingMessage(id: 'm1', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.parsed);
      final result = await service.retryRejected('m1');
      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure<Transaction>).error.code, 'message_not_rejected');
      expect(balances.credits, 0);
    });

    // حماية من الإيداع المضاعف: رسالة رُفضت أصلاً لأنها تكرار لعملية أخرى
    // سبق اعتمادها يجب ألا تُقبل عبر إعادة المحاولة، لأن `credit()` لا
    // يتحقق من التكرار بنفسه.
    test('retryRejected refuses a message rejected as a duplicate and never credits', () async {
      customers.store['c1'] = Customer(id: 'c1', displayName: 'عميل', status: CustomerStatus.active, createdAt: DateTime.utc(2026, 1, 1), updatedAt: DateTime.utc(2026, 1, 1));
      customers.byIdentifier['770123456'] = 'c1';
      messages.store['m1'] = IncomingMessage(id: 'm1', sender: 'bank', body: 'body', receivedAt: DateTime.utc(2026, 9, 12), status: MessageProcessingStatus.rejected);
      audit.logs.add(AuditLog(id: 'a1', entityType: 'message', entityId: 'm1', action: RejectionCodes.duplicateTransaction, occurredAt: DateTime.utc(2026, 9, 12, 1)));

      final result = await service.retryRejected('m1');

      expect(result, isA<Failure<Transaction>>());
      expect((result as Failure<Transaction>).error.code, 'retry_blocked_duplicate');
      expect(balances.credits, 0);
      expect(messages.store['m1']!.status, MessageProcessingStatus.rejected);
    });
  });
}

final class _FixedClock implements Clock {
  const _FixedClock();
  @override DateTime now() => DateTime.utc(2026, 9, 12, 12);
}
final class _PassthroughUow implements UnitOfWork {
  const _PassthroughUow();
  @override Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}
final class _FakeParser implements MessageParser {
  const _FakeParser(this.transfer);
  final ParsedTransfer transfer;
  @override Result<ParsedTransfer> parse(IncomingMessage message) => Success(ParsedTransfer(messageId: message.id, amount: transfer.amount, customerIdentifier: transfer.customerIdentifier, identifierType: transfer.identifierType, reference: transfer.reference));
}
final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};
  @override Future<Result<void>> save(IncomingMessage message) async { store[message.id] = message; return const Success(null); }
  @override Future<Result<IncomingMessage?>> findById(String id) async => Success(store[id]);
  @override Future<Result<IncomingMessage?>> findByExternalReference(String reference) async => const Success(null);
  @override Future<Result<List<IncomingMessage>>> pendingProcessing() async => Success(store.values.where((m) => m.status == MessageProcessingStatus.received || m.status == MessageProcessingStatus.parsed).toList());
  @override Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async => Success(store.values.where((m) => m.status == status).toList());
  @override
  Future<Result<int>> countByStatus(MessageProcessingStatus status) async =>
      Success(store.values.where((m) => m.status == status).length);

  @override
  Stream<int> watchCountByStatus(MessageProcessingStatus status) async* {
    yield store.values.where((m) => m.status == status).length;
  }

  @override Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async => Success(store.values.take(limit).toList());
  @override Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async { final m = store[id]!; store[id] = IncomingMessage(id: m.id, sender: m.sender, body: m.body, receivedAt: m.receivedAt, status: status, externalReference: m.externalReference, customerIdentifier: m.customerIdentifier); return const Success(null); }

  @override
  Future<Result<void>> delete(String id) async {
    store.remove(id);
    return const Success(null);
  }
}
final class _FakeCustomers implements CustomerRepository {
  final store = <String, Customer>{};
  final byIdentifier = <String, String>{};
  @override Future<Result<Customer?>> findById(String id) async => Success(store[id]);
  @override Future<Result<Customer?>> findByIdentifier(String value) async { final id = byIdentifier[value]; return Success(id == null ? null : store[id]); }
  @override Future<Result<void>> save(Customer customer) async { store[customer.id] = customer; return const Success(null); }
  @override Future<Result<void>> saveIdentifier(CustomerIdentifier identifier) async { byIdentifier[identifier.value] = identifier.customerId; return const Success(null); }
  @override Future<Result<List<Customer>>> search(String query) async => Success(store.values.toList());
  @override Future<Result<List<CustomerPhoneSuggestion>>> suggestPhonesByPrefix(String prefix, {int limit = 8}) async => const Success([]);
  @override Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId) async => const Success([]);
  @override Future<Result<List<CustomerAccountSnapshot>>> listAccountSnapshots({String query = '', String currencyCode = 'YER', int? limit, int offset = 0}) async => const Success([]);
}
final class _FakeCustomerService implements CustomerService {
  _FakeCustomerService(this.customers);
  final _FakeCustomers customers;
  int created = 0;
  @override Future<Result<Customer>> create({required String displayName, required CustomerIdentifierType identifierType, required String identifierValue, CustomerStatus status = CustomerStatus.active}) async { created++; final c = Customer(id: 'c-new-$created', displayName: displayName, status: status, createdAt: DateTime.utc(2026, 9, 12), updatedAt: DateTime.utc(2026, 9, 12)); customers.store[c.id] = c; customers.byIdentifier[identifierValue] = c.id; return Success(c); }
  @override Future<Result<Customer>> promoteToActive(String customerId) async { final c = customers.store[customerId]; if (c == null) return const Failure(AppFailure(code: 'customer_not_found', message: 'Customer was not found')); final updated = c.copyWith(status: CustomerStatus.active); customers.store[customerId] = updated; return Success(updated); }
  @override Future<Result<void>> blacklist(String customerId) async => const Success(null);
  @override Future<Result<void>> addIdentifier({required String customerId, required CustomerIdentifierType type, required String value, required bool isPrimary}) async => const Success(null);
  @override Future<Result<void>> bindPrimaryGsm({required String customerId, required String phone}) async { customers.byIdentifier[phone] = customerId; return const Success(null); }
}
final class _FakeBalances implements CustomerBalanceService {
  int credits = 0;
  @override Future<Result<Money>> getBalance({required String customerId, required String currencyCode}) async => Success(Money(minorUnits: 0, currencyCode: currencyCode));
  @override Future<Result<Money>> getTotalOutstanding({required String currencyCode}) async => Success(Money(minorUnits: 0, currencyCode: currencyCode));
  @override Future<Result<Transaction>> credit({required String customerId, required Money amount, String? reference, String? reason}) async { credits++; return Success(Transaction(id: 'tx-$credits', customerId: customerId, type: TransactionType.deposit, status: TransactionStatus.completed, amount: amount, createdAt: DateTime.utc(2026, 9, 12), reference: reference)); }
  @override
  Future<Result<Transaction>> debit({required String customerId, required Money amount, String? reference, String? reason}) async =>
      Success(Transaction(id: 'debit', customerId: customerId, type: TransactionType.withdrawal, status: TransactionStatus.completed, amount: amount, createdAt: DateTime.utc(2026, 1, 1), reference: reference));
  @override
  Future<Result<CustomerAccountSummary>> getAccountSummary({required String customerId, required String currencyCode}) async =>
      Success(CustomerAccountSummary(balance: Money(minorUnits: 0, currencyCode: currencyCode), totalSalesMinor: 0, totalDepositsMinor: 0, totalWithdrawalsMinor: 0, totalSettlementsMinor: 0, openAdvancesCount: 0, openAdvancesMinor: 0, transactionCount: 0));
}
final class _FakeAudit implements AuditLogRepository {
  final logs = <AuditLog>[];
  @override Future<Result<void>> append(AuditLog log) async { logs.add(log); return const Success(null); }
  @override Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async => Success(logs.where((l) => l.entityId == entityId).toList());
}
