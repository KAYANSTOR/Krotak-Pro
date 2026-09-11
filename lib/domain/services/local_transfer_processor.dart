import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_customer_identity_resolver.dart';
import 'services.dart';

/// Processes a [ParsedTransfer]:
/// 1. Load message & enforce already-processed
/// 2. Resolve customer identity (never send to account/name tokens)
/// 3. Credit wallet (deposit)
/// 4. Mark message processed
/// 5. Write audit log
///
/// All steps run inside [UnitOfWork] for atomicity.
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
  Future<Result<Transaction>> process(ParsedTransfer transfer) {
    return unitOfWork.run(() async {
      // 1. Load & guard message
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

      // 2. Resolve customer identity — explicit Unresolved, no guessing
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
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.rejected,
        );
        await auditLogs.append(
          AuditLog(
            id: ids.next('audit'),
            entityType: 'message',
            entityId: message.id,
            action: 'transfer_unresolved',
            occurredAt: clock.now(),
            payloadJson:
                '{"code":"${resolution.reasonCode}","identifierType":"${transfer.identifierType.name}","identifier":"${transfer.customerIdentifier}"}',
          ),
        );
        return Failure(
          AppFailure(
            code: resolution.reasonCode ?? 'unresolved_identity',
            message: resolution.reasonMessage ??
                'Could not resolve customer identity',
          ),
        );
      }
      final customer = resolution.customer!;

      // Guard: account/name/reference must never be treated as delivery phone.
      if (transfer.identifierType != TransferIdentifierType.phone &&
          resolution.deliveryPhone != null &&
          resolution.deliveryPhone == transfer.customerIdentifier) {
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.rejected,
        );
        return const Failure(
          AppFailure(
            code: 'identifier_type_mismatch',
            message:
                'Non-phone identifier cannot equal delivery phone without mapping',
          ),
        );
      }

      // 3. Credit
      final creditResult = await balances.credit(
        customerId: customer.id,
        amount: transfer.amount,
        reference: transfer.reference,
      );
      if (creditResult is Failure<Transaction>) {
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.failed,
        );
        return Failure(creditResult.error);
      }
      final tx = (creditResult as Success<Transaction>).value;

      // 4. Mark processed
      await messages.updateStatus(
        message.id,
        MessageProcessingStatus.processed,
      );

      // 5. Audit
      final delivery = resolution.deliveryPhone ?? '';
      await auditLogs.append(
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

      return Success(tx);
    });
  }
}
