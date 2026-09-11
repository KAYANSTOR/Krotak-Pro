import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
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
        AppFailure(code: 'message_not_found', message: 'Message was not found'),
      );
    }

    final operationId = _operationId(transfer);
    final txRepo = transactions;
    if (txRepo != null) {
      final existingLedger =
          await txRepo.findByReference('sale-op:$operationId');
      if (existingLedger is Failure<Transaction?>) {
        return Failure<Transaction>(existingLedger.error);
      }
      final existing = (existingLedger as Success<Transaction?>).value;
      if (existing != null) {
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        return Success<Transaction>(existing);
      }
    }

    final resolutionResult = await _resolver.resolve(
      identifierValue: transfer.customerIdentifier,
      identifierType: transfer.identifierType,
    );
    if (resolutionResult is Failure<CustomerIdentityResolution>) {
      return Failure<Transaction>(resolutionResult.error);
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
      return Failure<Transaction>(failure);
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
      final credit = await balances.credit(
        customerId: resolution.customer!.id,
        amount: transfer.amount,
        reference: transfer.reference,
      );
      if (credit is Failure<Transaction>) {
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.failed,
          action: 'transfer_credit_failed',
          error: credit.error,
          transfer: transfer,
          deliveryPhone: resolution.deliveryPhone,
        );
        return Failure<Transaction>(credit.error);
      }
      final tx = (credit as Success<Transaction>).value;
      await messages.updateStatus(message.id, MessageProcessingStatus.processed);
      return Success<Transaction>(tx);
    }

    final categoriesRepo = categories!;
    final cardsRepo = cards!;
    final inventoryService = inventory!;
    final saleCompleter = reservedSales!;
    final sender = messageSender!;
    final transactionRepo = transactions!;
    final customer = resolution.customer!;
    final destination = resolution.deliveryPhone?.trim() ?? '';
    if (destination.isEmpty) {
      const failure = AppFailure(
        code: 'delivery_phone_missing',
        message: 'Customer has no resolved delivery phone',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: 'transfer_rejected',
        error: failure,
        transfer: transfer,
      );
      return const Failure<Transaction>(failure);
    }

    final deliveryState = await _deliveryState(message.id);
    if (deliveryState != null) {
      final ensured = await _ensureReservation(
        cardId: deliveryState.cardId,
        reservationId: deliveryState.reservationId,
        categoryId: deliveryState.categoryId,
        now: clock.now(),
        cardsRepo: cardsRepo,
      );
      if (ensured is Failure<Card>) {
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.failed,
          action: 'transfer_delivery_recovery_failed',
          error: ensured.error,
          transfer: transfer,
          deliveryPhone: destination,
        );
        return Failure<Transaction>(ensured.error);
      }
      final completed = await saleCompleter.completeReservedSale(
        customerId: customer.id,
        cardId: deliveryState.cardId,
        reservationId: deliveryState.reservationId,
        operationId: operationId,
      );
      if (completed is Failure<Sale>) {
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.failed,
          action: 'transfer_sale_recovery_failed',
          error: completed.error,
          transfer: transfer,
          deliveryPhone: destination,
        );
        return Failure<Transaction>(completed.error);
      }
      final ledger =
          await transactionRepo.findByReference('sale-op:$operationId');
      if (ledger is Success<Transaction?> && ledger.value != null) {
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        return Success<Transaction>(ledger.value!);
      }
      const failure = AppFailure(
        code: 'sale_ledger_missing',
        message: 'Sale completed but its ledger record could not be found',
      );
      return const Failure<Transaction>(failure);
    }

    final allCategories = await categoriesRepo.listAll();
    if (allCategories is Failure<List<CardCategory>>) {
      return Failure<Transaction>(allCategories.error);
    }
    final matches = (allCategories as Success<List<CardCategory>>).value
        .where(
          (category) =>
              category.isActive &&
              category.faceValue.currencyCode == transfer.amount.currencyCode &&
              category.faceValue.minorUnits == transfer.amount.minorUnits,
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      const failure = AppFailure(
        code: 'unmatched_amount',
        message: 'No active card category matches the transfer amount',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: 'transfer_unmatched_amount',
        error: failure,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return const Failure<Transaction>(failure);
    }
    if (matches.length > 1) {
      const failure = AppFailure(
        code: 'ambiguous_amount_category',
        message: 'Multiple active card categories match the transfer amount',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: 'transfer_ambiguous_category',
        error: failure,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return const Failure<Transaction>(failure);
    }

    final category = matches.single;
    final reservationId = 'transfer-reservation:$operationId';
    final now = clock.now();
    final reserved = await inventoryService.reserveAvailableCard(
      categoryId: category.id,
      reservationId: reservationId,
      now: now,
      expiresAt: now.add(reservationTtl),
    );
    if (reserved is Failure<Card>) {
      final failure = reserved.error.code == 'card_unavailable'
          ? const AppFailure(
              code: 'out_of_stock',
              message: 'No available card exists in the matching category',
            )
          : reserved.error;
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.rejected,
        action: failure.code == 'out_of_stock'
            ? 'transfer_out_of_stock'
            : 'transfer_reservation_failed',
        error: failure,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(failure);
    }
    final card = (reserved as Success<Card>).value;

    final credit = await balances.credit(
      customerId: customer.id,
      amount: transfer.amount,
      reference: transfer.reference,
    );
    if (credit is Failure<Transaction>) {
      await inventoryService.releaseReservation(
        cardId: card.id,
        reservationId: reservationId,
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'transfer_credit_failed',
        error: credit.error,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(credit.error);
    }

    final body =
        'بطاقة الإنترنت\nالرقم: ${card.serialNumber}\nالرمز: ${card.secretCode}';
    final sent = await sender.send(destination: destination, body: body);
    if (sent is Failure<void>) {
      await inventoryService.releaseReservation(
        cardId: card.id,
        reservationId: reservationId,
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'sms_delivery_failed',
        error: sent.error,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(sent.error);
    }

    final deliveryAudit = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'message',
        entityId: message.id,
        action: 'sms_delivery_succeeded',
        occurredAt: clock.now(),
        payloadJson:
            '{"operationId":"$operationId","cardId":"${card.id}","categoryId":"${category.id}","reservationId":"$reservationId","destination":"$destination"}',
      ),
    );
    if (deliveryAudit is Failure<void>) {
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'sms_delivery_state_persist_failed',
        error: deliveryAudit.error,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(deliveryAudit.error);
    }

    final completed = await saleCompleter.completeReservedSale(
      customerId: customer.id,
      cardId: card.id,
      reservationId: reservationId,
      operationId: operationId,
    );
    if (completed is Failure<Sale>) {
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'transfer_sale_commit_failed',
        error: completed.error,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(completed.error);
    }

    final ledger =
        await transactionRepo.findByReference('sale-op:$operationId');
    if (ledger is Failure<Transaction?>) return Failure<Transaction>(ledger.error);
    final saleLedger = (ledger as Success<Transaction?>).value;
    if (saleLedger == null) {
      const failure = AppFailure(
        code: 'sale_ledger_missing',
        message: 'Sale completed but its ledger record could not be found',
      );
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'transfer_ledger_missing',
        error: failure,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return const Failure<Transaction>(failure);
    }

    await messages.updateStatus(message.id, MessageProcessingStatus.processed);
    return Success<Transaction>(saleLedger);
  }

  String _operationId(ParsedTransfer transfer) {
    final ref = transfer.reference.trim();
    return ref.isNotEmpty ? ref : 'message:${transfer.messageId}';
  }

  Future<_DeliveryState?> _deliveryState(String messageId) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return null;
    final entries = (logs as Success<List<AuditLog>>).value
        .where((log) => log.action == 'sms_delivery_succeeded')
        .toList(growable: false);
    if (entries.isEmpty) return null;
    final payload = entries.last.payloadJson ?? '';
    final cardId = _field(payload, 'cardId');
    final reservationId = _field(payload, 'reservationId');
    final categoryId = _field(payload, 'categoryId');
    if (cardId == null || reservationId == null || categoryId == null) return null;
    return _DeliveryState(
      cardId: cardId,
      reservationId: reservationId,
      categoryId: categoryId,
    );
  }

  Future<Result<Card>> _ensureReservation({
    required String cardId,
    required String reservationId,
    required String categoryId,
    required DateTime now,
    required CardRepository cardsRepo,
  }) async {
    final found = await cardsRepo.findById(cardId);
    if (found is Failure<Card?>) return Failure<Card>(found.error);
    final card = (found as Success<Card?>).value;
    if (card == null) {
      return const Failure<Card>(
        AppFailure(code: 'card_not_found', message: 'Card was not found'),
      );
    }
    if (card.status == CardStatus.reserved &&
        card.reservation.reservationId == reservationId) {
      return Success<Card>(card);
    }
    if (card.status == CardStatus.sold) {
      return const Failure<Card>(
        AppFailure(
          code: 'delivered_card_already_sold',
          message: 'The already-delivered card was already sold',
        ),
      );
    }
    if (card.status != CardStatus.available || card.categoryId != categoryId) {
      return const Failure<Card>(
        AppFailure(
          code: 'delivered_card_unavailable',
          message: 'The already-delivered card is no longer safely recoverable',
        ),
      );
    }
    final reserved = await cardsRepo.reserve(
      card.id,
      CardReservation(
        reservationId: reservationId,
        reservedAt: now,
        expiresAt: now.add(reservationTtl),
      ),
    );
    if (reserved is Failure<void>) return Failure<Card>(reserved.error);
    final reloaded = await cardsRepo.findById(card.id);
    if (reloaded is Failure<Card?>) return Failure<Card>(reloaded.error);
    final result = (reloaded as Success<Card?>).value;
    if (result == null) {
      return const Failure<Card>(
        AppFailure(code: 'card_not_found', message: 'Card was not found'),
      );
    }
    return Success<Card>(result);
  }

  String? _field(String payload, String name) {
    final match = RegExp('"$name":"([^"]*)"').firstMatch(payload);
    return match?.group(1);
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
            '{"code":"${error.code}","reference":"${transfer.reference}","operationId":"${_operationId(transfer)}","identifierType":"${transfer.identifierType.name}","identifier":"${transfer.customerIdentifier}","deliveryPhone":"${deliveryPhone ?? ''}"}',
      ),
    );
  }
}

final class _DeliveryState {
  const _DeliveryState({
    required this.cardId,
    required this.reservationId,
    required this.categoryId,
  });

  final String cardId;
  final String reservationId;
  final String categoryId;
}
