import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';

/// Processes a [ParsedTransfer]:
/// 1. Load message & enforce already-processed
/// 2. Resolve customer by identifier
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
  });

  final MessageRepository messages;
  final CustomerRepository customers;
  final CustomerBalanceService balances;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

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

      // 2. Resolve customer
      final customerResult =
          await customers.findByIdentifier(transfer.customerIdentifier);
      if (customerResult is Failure<Customer?>) {
        return Failure(customerResult.error);
      }
      final customer = (customerResult as Success<Customer?>).value;
      if (customer == null) {
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.rejected,
        );
        return const Failure(
          AppFailure(
            code: 'customer_not_found',
            message: 'No customer matches the transfer identifier',
          ),
        );
      }
      if (customer.status != CustomerStatus.active) {
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.rejected,
        );
        return const Failure(
          AppFailure(
            code: 'customer_not_active',
            message: 'Customer is not active',
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
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: message.id,
          action: 'transfer_processed',
          occurredAt: clock.now(),
          payloadJson:
              '{"transactionId":"${tx.id}","reference":"${transfer.reference}"}',
        ),
      );

      return Success(tx);
    });
  }
}
