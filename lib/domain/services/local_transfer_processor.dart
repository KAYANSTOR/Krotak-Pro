import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_customer_identity_resolver.dart';
import 'services.dart';

/// Processes a [ParsedTransfer] without losing terminal failure state to rollback.
///
/// Financial success remains atomic with the processed/audit state. Rejected and
/// failed message states are persisted after the business transaction rolls back,
/// so recovery can observe and act on the actual terminal state.
final class LocalTransferProcessor implements TransferProcessor {
  const LocalTransferProcessor({
    required this.messages,
    required this.customers,
    required this.balances,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.identityResolver,
  });

  final MessageRepository messages;
  final CustomerRepository customers;
  final CustomerBalanceService balances;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  /// When null, a resolver is built from [customers] (keeps tests simple).
  final LocalCustomerIdentityResolver? identityResolver;

  LocalCustomerIdentityResolver get _resolver =>
      identityResolver ?? LocalCustomerIdentityResolver(customers: customers);

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    final msgResult = await messages.findById(transfer.messageId);
    if (msgResult is Failure<IncomingMessage?>) {
      return Failure(msgResult.error);
    }
    final message = (msgResult as Success<IncomingMessage?>).value;
    if (message == null) {
      return const Failure(
        AppFailure(code: 'message_not_found', message: 'Message was not found'),
      );
    }

    if (message.status == MessageProcessingStatus.processed) {
      return const Failure(
        AppFailure(
          code: 'message_already_processed',
          message: 'Message was already processed',
        ),
      );
    }

    final resolutionResult = await _resolver.resolve(
      identifierValue: transfer.customerIdentifier,
      identifierType: transfer.identifierType,
    );
    if (resolutionResult is Failure<CustomerIdentityResolution>) {
      return Failure(resolutionResult.error);
    }
    final resolution =
        (resolutionResult as Success<CustomerIdentityResolution>).value;
    if (!resolution.isResolved || resolution.customer == null) {
      final failure = AppFailure(
        code: resolution.reasonCode ?? 'unresolved_identity',
        message: resolution.reasonMessage ?? 'Could not resolve customer identity',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: 'transfer_unresolved',
        error: failure,
        transfer: transfer,
        deliveryPhone: resolution.deliveryPhone,
      );
      return Failure(failure);
    }

    final customer = resolution.customer!;
    if (transfer.identifierType != TransferIdentifierType.phone &&
        resolution.deliveryPhone != null &&
        resolution.deliveryPhone == transfer.customerIdentifier) {
      const failure = AppFailure(
        code: 'identifier_type_mismatch',
        message:
            'Non-phone identifier cannot equal delivery phone without mapping',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: 'transfer_rejected',
        error: failure,
        transfer: transfer,
        deliveryPhone: resolution.deliveryPhone,
      );
      return const Failure(failure);
    }

    final result = await unitOfWork.run(() async {
      final creditResult = await balances.credit(
        customerId: customer.id,
        amount: transfer.amount,
        reference: transfer.reference,
      );
      if (creditResult is Failure<Transaction>) {
        return Failure(creditResult.error);
      }
      final tx = (creditResult as Success<Transaction>).value;

      final marked = await messages.updateStatus(
        message.id,
        MessageProcessingStatus.processed,
      );
      if (marked is Failure<void>) {
        return Failure(marked.error);
      }

      final delivery = resolution.deliveryPhone ?? '';
      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: message.id,
          action: 'transfer_processed',
          occurredAt: clock.now(),
          payloadJson:
              '{"transactionId":"${tx.id}","reference":"${transfer.reference}","identifierType":"${transfer.identifierType.name}","deliveryPhone":"$delivery"}',
        ),
      );
      if (audited is Failure<void>) {
        return Failure(audited.error);
      }

      return Success(tx);
    });

    if (result is Success<Transaction>) {
      return result;
    }

    final failure = (result as Failure<Transaction>).error;
    await _persistTerminalFailure(
      messageId: message.id,
      status: MessageProcessingStatus.failed,
      action: 'transfer_failed',
      error: failure,
      transfer: transfer,
      deliveryPhone: resolution.deliveryPhone,
    );
    return Failure(failure);
  }

  Future<void> _persistTerminalFailure({
    required String messageId,
    required MessageProcessingStatus status,
    required String action,
    required AppFailure error,
    required ParsedTransfer transfer,
    String? deliveryPhone,
  }) async {
    await messages.updateStatus(messageId, status);
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'message',
        entityId: messageId,
        action: action,
        occurredAt: clock.now(),
        payloadJson:
            '{"code":"${error.code}","reference":"${transfer.reference}","identifierType":"${transfer.identifierType.name}","identifier":"${transfer.customerIdentifier}","deliveryPhone":"${deliveryPhone ?? ''}"}',
      ),
    );
  }
}
