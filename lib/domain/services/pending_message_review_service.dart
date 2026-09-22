import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_customer_identity_resolver.dart';
import 'payment_source_guard.dart';
import 'services.dart';

final class PendingMessageReviewService {
  const PendingMessageReviewService({
    required this.messages,
    required this.parser,
    required this.customers,
    required this.customerService,
    required this.balances,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    required this.sourceGuard,
    this.identityResolver,
  });

  final MessageRepository messages;
  final MessageParser parser;
  final CustomerRepository customers;
  final CustomerService customerService;
  final CustomerBalanceService balances;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;
  final PaymentSourceGuard sourceGuard;
  final LocalCustomerIdentityResolver? identityResolver;
  LocalCustomerIdentityResolver get _resolver => identityResolver ?? LocalCustomerIdentityResolver(customers: customers);

  Future<Result<List<IncomingMessage>>> listPending() async {
    // Commercial pending queue: unmatched-amount review stays on `parsed`
    // (transfer_unmatched_amount_pending). Explicit `pending` status is also
    // included so operator-visible notifications and deferred rows appear.
    final parsed = await messages.listByStatus(MessageProcessingStatus.parsed);
    if (parsed is Failure<List<IncomingMessage>>) return parsed;
    final pending = await messages.listByStatus(MessageProcessingStatus.pending);
    if (pending is Failure<List<IncomingMessage>>) return pending;

    final map = <String, IncomingMessage>{};
    for (final m in (parsed as Success<List<IncomingMessage>>).value) {
      map[m.id] = m;
    }
    for (final m in (pending as Success<List<IncomingMessage>>).value) {
      map[m.id] = m;
    }
    final list = map.values.toList(growable: false)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return Success(list);
  }

  Future<Result<Transaction>> approve(String messageId) async {
    final found = await messages.findById(messageId);
    if (found is Failure<IncomingMessage?>) return Failure(found.error);
    final message = (found as Success<IncomingMessage?>).value;
    if (message == null) return const Failure(AppFailure(code: 'message_not_found', message: 'Message was not found'));
    if (message.status == MessageProcessingStatus.processed) return const Failure(AppFailure(code: 'message_already_processed', message: 'Message was already approved'));
    if (message.status == MessageProcessingStatus.rejected) return const Failure(AppFailure(code: 'message_already_rejected', message: 'Message was already rejected'));
    if (message.status != MessageProcessingStatus.parsed &&
        message.status != MessageProcessingStatus.received &&
        message.status != MessageProcessingStatus.pending) {
      return const Failure(AppFailure(code: 'message_not_pending', message: 'Message is not pending review'));
    }

    final event = _eventForMessage(message);
    final sourceAuthorization = await sourceGuard.authorize(event);
    if (sourceAuthorization is Failure<void>) return Failure(sourceAuthorization.error);

    final parseResult = parser.parse(message);
    if (parseResult is Failure<ParsedTransfer>) return Failure(parseResult.error);
    final transfer = (parseResult as Success<ParsedTransfer>).value;
    final templateAuthorization = await sourceGuard.authorize(
      event,
      matchedTemplateId: transfer.templateId,
    );
    if (templateAuthorization is Failure<void>) return Failure(templateAuthorization.error);

    final resolutionResult = await _resolver.resolve(identifierValue: transfer.customerIdentifier, identifierType: transfer.identifierType);
    if (resolutionResult is Failure<CustomerIdentityResolution>) return Failure(resolutionResult.error);
    var resolution = (resolutionResult as Success<CustomerIdentityResolution>).value;

    if (!resolution.isResolved || resolution.customer == null) {
      if (transfer.identifierType != TransferIdentifierType.phone) return Failure(AppFailure(code: resolution.reasonCode ?? 'unresolved_identity', message: resolution.reasonMessage ?? 'Cannot approve without a resolvable customer'));
      final created = await customerService.create(displayName: transfer.customerIdentifier, identifierType: CustomerIdentifierType.phoneNumber, identifierValue: transfer.customerIdentifier);
      if (created is Failure<Customer>) return Failure(created.error);
      final customer = (created as Success<Customer>).value;
      final identifiers = await customers.listIdentifiers(customer.id);
      if (identifiers is Failure<List<CustomerIdentifier>>) return Failure(identifiers.error);
      final matched = (identifiers as Success<List<CustomerIdentifier>>).value.where((item) => item.type == CustomerIdentifierType.phoneNumber).firstOrNull;
      resolution = CustomerIdentityResolution.resolved(customer: customer, deliveryPhone: transfer.customerIdentifier, matchedIdentifier: matched);
    }

    final customer = resolution.customer!;
    final creditRef = transfer.reference.trim().isNotEmpty ? 'pending-approve:${transfer.reference.trim()}' : 'pending-approve:$messageId';
    final credit = await balances.credit(customerId: customer.id, amount: transfer.amount, reference: creditRef);
    if (credit is Failure<Transaction>) return Failure(credit.error);
    final tx = (credit as Success<Transaction>).value;
    await messages.updateStatus(messageId, MessageProcessingStatus.processed);
    await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'message', entityId: messageId, action: 'pending_message_approved', occurredAt: clock.now(), payloadJson: '{"transactionId":"${tx.id}","customerId":"${customer.id}","amount":${transfer.amount.minorUnits},"currency":"${transfer.amount.currencyCode}","reference":"${transfer.reference}","sender":"${message.sender}"}'));
    return Success(tx);
  }

  PaymentEvent _eventForMessage(IncomingMessage message) {
    final sender = message.sender.trim();
    if (sender.startsWith('notification:')) {
      return PaymentEvent(
        channel: PaymentChannel.notification,
        sourceKey: sender,
        body: message.body,
        receivedAt: message.receivedAt,
        packageName: sender.substring('notification:'.length),
      );
    }
    return PaymentEvent(
      channel: PaymentChannel.sms,
      sourceKey: sender,
      body: message.body,
      receivedAt: message.receivedAt,
    );
  }

  Future<Result<void>> reject(String messageId, {String? reason}) async {
    final found = await messages.findById(messageId);
    if (found is Failure<IncomingMessage?>) return Failure(found.error);
    final message = (found as Success<IncomingMessage?>).value;
    if (message == null) return const Failure(AppFailure(code: 'message_not_found', message: 'Message was not found'));
    if (message.status == MessageProcessingStatus.processed) return const Failure(AppFailure(code: 'message_already_processed', message: 'Processed messages cannot be rejected'));
    if (message.status == MessageProcessingStatus.rejected) return const Success(null);
    await messages.updateStatus(messageId, MessageProcessingStatus.rejected);
    final safeReason = (reason ?? 'رفض من شاشة الرسائل المعلّقة').replaceAll('"', '\\"');
    await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'message', entityId: messageId, action: 'pending_message_rejected', occurredAt: clock.now(), payloadJson: '{"reason":"$safeReason","sender":"${message.sender}","previousStatus":"${message.status.name}"}'));
    return const Success(null);
  }
}
