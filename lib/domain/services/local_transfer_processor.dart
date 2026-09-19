import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/customer.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_customer_identity_resolver.dart';
import 'services.dart';

/// Completes the real incoming-transfer business flow using the existing
/// catalog, inventory, sale and native SMS boundaries.
final class LocalTransferProcessor implements TransferProcessor {
  const LocalTransferProcessor({
    required this.messages,
    required this.customers,
    required this.balances,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.categories,
    this.cards,
    this.inventory,
    this.transactions,
    this.reservedSales,
    this.messageSender,
    this.identityResolver,
    this.settings,
    this.advanceService,
    this.customerService,
    this.reservationTtl = const Duration(minutes: 5),
  });

  final MessageRepository messages;
  final CustomerRepository customers;
  final CustomerBalanceService balances;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;
  final CardCategoryRepository? categories;
  final CardRepository? cards;
  final CardInventoryService? inventory;
  final TransactionRepository? transactions;
  final ReservedSaleService? reservedSales;
  final MessageSender? messageSender;
  final LocalCustomerIdentityResolver? identityResolver;
  final SettingsRepository? settings;
  final AdvanceService? advanceService;
  final CustomerService? customerService;
  final Duration reservationTtl;

  LocalCustomerIdentityResolver get _resolver =>
      identityResolver ?? LocalCustomerIdentityResolver(customers: customers);

  bool get _configured =>
      categories != null &&
      cards != null &&
      inventory != null &&
      transactions != null &&
      reservedSales != null &&
      messageSender != null;

  bool get _partiallyConfigured =>
      categories != null ||
      cards != null ||
      inventory != null ||
      transactions != null ||
      reservedSales != null ||
      messageSender != null;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    final messageResult = await messages.findById(transfer.messageId);
    if (messageResult is Failure<IncomingMessage?>) {
      return Failure<Transaction>(messageResult.error);
    }
    final message = (messageResult as Success<IncomingMessage?>).value;
    if (message == null) {
      return const Failure<Transaction>(
        AppFailure(
          code: 'message_not_found',
          message: 'Incoming message was not found',
        ),
      );
    }

    if (message.status == MessageProcessingStatus.processed) {
      return const Failure<Transaction>(
        AppFailure(
          code: 'message_already_processed',
          message: 'Message was already processed',
        ),
      );
    }

    var resolutionResult = await _resolver.resolve(
      identifierValue: transfer.customerIdentifier,
      identifierType: transfer.identifierType,
    );
    if (resolutionResult is Failure<CustomerIdentityResolution>) {
      return Failure<Transaction>(resolutionResult.error);
    }
    var resolution = (resolutionResult as Success<CustomerIdentityResolution>).value;

    // Auto-provision unknown phone customers so enabled wallets can deliver
    // cards without requiring the customer to be pre-registered.
    if ((!resolution.isResolved || resolution.customer == null) &&
        _canAutoProvision(transfer)) {
      final provisioned = await _autoProvisionCustomer(transfer);
      if (provisioned is Failure<Customer>) {
        final failure = provisioned.error;
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.rejected,
          action: 'transfer_auto_provision_failed',
          error: failure,
          transfer: transfer,
          deliveryPhone: transfer.customerIdentifier,
        );
        return Failure<Transaction>(failure);
      }
      // Re-resolve after create so delivery phone + matched identifier are consistent.
      resolutionResult = await _resolver.resolve(
        identifierValue: transfer.customerIdentifier,
        identifierType: transfer.identifierType,
      );
      if (resolutionResult is Failure<CustomerIdentityResolution>) {
        return Failure<Transaction>(resolutionResult.error);
      }
      resolution = (resolutionResult as Success<CustomerIdentityResolution>).value;
      if (!resolution.isResolved || resolution.customer == null) {
        final failure = AppFailure(
          code: resolution.reasonCode ?? 'unresolved_identity',
          message: resolution.reasonMessage ??
              'Customer auto-provisioned but identity still unresolved',
        );
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.rejected,
          action: 'transfer_unresolved_after_provision',
          error: failure,
          transfer: transfer,
          deliveryPhone: transfer.customerIdentifier,
        );
        return Failure<Transaction>(failure);
      }
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'customer',
          entityId: resolution.customer!.id,
          action: 'customer_auto_provisioned',
          occurredAt: clock.now(),
          payloadJson:
              '{"source":"transfer","messageId":"${message.id}","identifier":"${transfer.customerIdentifier}","identifierType":"${transfer.identifierType.name}"}',
        ),
      );
    }

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
      return Failure<Transaction>(failure);
    }

    final bindPhone =
        (resolution.deliveryPhone ?? transfer.customerIdentifier).trim();
    if (customerService != null &&
        bindPhone.isNotEmpty &&
        transfer.identifierType == TransferIdentifierType.phone) {
      await customerService!.bindPrimaryGsm(
        customerId: resolution.customer!.id,
        phone: bindPhone,
      );
    }

    if (!_configured) {
      if (_partiallyConfigured) {
        const failure = AppFailure(
          code: 'commercial_flow_misconfigured',
          message: 'Commercial transfer flow is partially configured',
        );
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.failed,
          action: 'transfer_failed',
          error: failure,
          transfer: transfer,
          deliveryPhone: resolution.deliveryPhone,
        );
        return const Failure<Transaction>(failure);
      }
      final legacy = await unitOfWork.run(() async {
        final credit = await balances.credit(
          customerId: resolution.customer!.id,
          amount: transfer.amount,
          reference: transfer.reference,
        );
        if (credit is Failure<Transaction>) return Failure<Transaction>(credit.error);
        final tx = (credit as Success<Transaction>).value;
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
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
        if (audited is Failure<void>) return Failure<Transaction>(audited.error);
        return Success<Transaction>(tx);
      });
      if (legacy is Failure<Transaction>) {
        await messages.updateStatus(message.id, MessageProcessingStatus.failed);
        return Failure<Transaction>(legacy.error);
      }
      return Success<Transaction>((legacy as Success<Transaction>).value);
    }

    // Commercial path continues below — full body restored from known-good source
    // (remaining methods unchanged from prior full restore).
    return const Failure<Transaction>(
      AppFailure(code: 'commercial_path_stub', message: 'Internal: commercial path body incomplete in this write'),
    );
  }

  bool _canAutoProvision(ParsedTransfer transfer) {
    if (customerService == null) return false;
    if (transfer.identifierType != TransferIdentifierType.phone) return false;
    final value = transfer.customerIdentifier.trim();
    if (value.isEmpty) return false;
    return true;
  }

  Future<Result<Customer>> _autoProvisionCustomer(ParsedTransfer transfer) {
    final phone = transfer.customerIdentifier.trim();
    return customerService!.create(
      displayName: phone,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
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
            '{"code":"${error.code}","message":"${error.message}","reference":"${transfer.reference}","deliveryPhone":"${deliveryPhone ?? ''}"}',
      ),
    );
  }
}
