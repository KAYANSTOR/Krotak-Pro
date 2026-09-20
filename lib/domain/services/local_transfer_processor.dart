import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/customer.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_customer_identity_resolver.dart';
import 'contact_directory.dart';
import 'services.dart';
import 'local_pos_account_registry.dart';
import 'local_category_commission_store.dart';
import 'pos_wholesale_pricing.dart';

/// Completes the real incoming-transfer business flow using the existing
/// catalog, inventory, sale and native SMS boundaries.
final class LocalTransferProcessor implements TransferProcessor {
  LocalTransferProcessor({
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
    this.contactDirectory,
    this.posRegistry,
    this.categoryCommissionStore,
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
  final ContactDirectory? contactDirectory;
  final LocalPosAccountRegistry? posRegistry;
  final LocalCategoryCommissionStore? categoryCommissionStore;
  final Duration reservationTtl;

  List<CardCategory>? _categoryCache;
  DateTime? _categoryCacheAt;
  static const Duration _categoryCacheTtl = Duration(seconds: 45);

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
      final existingLedger = await txRepo.findByReference('sale-op:$operationId');
      if (existingLedger is Failure<Transaction?>) {
        return Failure<Transaction>(existingLedger.error);
      }
      final existing = (existingLedger as Success<Transaction?>).value;
      if (existing != null) {
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        return Success<Transaction>(existing);
      }
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

    // Auto-provision unknown phone senders from enabled-wallet transfers so
    // card delivery proceeds without a pre-registered customer account.
    if ((!resolution.isResolved || resolution.customer == null) &&
        customerService != null &&
        _canAutoProvision(transfer)) {
      final provisioned = await _autoProvisionCustomer(transfer);
      if (provisioned is Success<Customer>) {
        resolutionResult = await _resolver.resolve(
          identifierValue: transfer.customerIdentifier,
          identifierType: transfer.identifierType,
        );
        if (resolutionResult is Failure<CustomerIdentityResolution>) {
          return Failure<Transaction>(resolutionResult.error);
        }
        resolution =
            (resolutionResult as Success<CustomerIdentityResolution>).value;
        await auditLogs.append(
          AuditLog(
            id: ids.next('audit'),
            entityType: 'message',
            entityId: message.id,
            action: 'ledger_account_auto_provisioned',
            occurredAt: clock.now(),
            payloadJson:
                '{\"customerId\":\"${provisioned.value.id}\",\"identifier\":\"${transfer.customerIdentifier}\",\"identifierType\":\"${transfer.identifierType.name}\"}',
          ),
        );
      }
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

    // If account was provisional but the phone is now in contacts, promote
    // to a full customer and adopt the contact display name.
    final liveCustomer = resolution.customer;
    if (liveCustomer != null &&
        liveCustomer.status == CustomerStatus.provisional &&
        customerService != null &&
        contactDirectory != null) {
      final match = await contactDirectory!.findByPhone(
        transfer.customerIdentifier,
      );
      if (match != null && match.displayName.trim().isNotEmpty) {
        final promoted = await customerService!.promoteToActive(liveCustomer.id);
        if (promoted is Success<Customer>) {
          final named = promoted.value.copyWith(
            displayName: match.displayName.trim(),
            updatedAt: clock.now(),
          );
          await customers.save(named);
          resolutionResult = await _resolver.resolve(
            identifierValue: transfer.customerIdentifier,
            identifierType: transfer.identifierType,
          );
          if (resolutionResult is Success<CustomerIdentityResolution>) {
            resolution =
                (resolutionResult as Success<CustomerIdentityResolution>).value;
          }
          await auditLogs.append(
            AuditLog(
              id: ids.next('audit'),
              entityType: 'customer',
              entityId: named.id,
              action: 'promoted_from_contacts',
              occurredAt: clock.now(),
              payloadJson:
                  '{\"phone\":\"${transfer.customerIdentifier}\",\"displayName\":\"${match.displayName.trim()}\"}',
            ),
          );
        }
      }
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
          reference: transfer.reference.isEmpty ? null : transfer.reference,
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
                '{\"transactionId\":\"${tx.id}\",\"reference\":\"${transfer.reference}\",\"identifierType\":\"${transfer.identifierType.name}\",\"deliveryPhone\":\"$delivery\"}',
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

    final deliveryStateResult = await _deliveryState(message.id);
    if (deliveryStateResult is Failure<_DeliveryState?>) {
      await messages.updateStatus(message.id, MessageProcessingStatus.failed);
      return Failure<Transaction>(deliveryStateResult.error);
    }
    final deliveryState = (deliveryStateResult as Success<_DeliveryState?>).value;
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
      final ledger = await transactionRepo.findByReference('sale-op:$operationId');
      if (ledger is Success<Transaction?> && ledger.value != null) {
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        return Success<Transaction>(ledger.value!);
      }
      return const Failure<Transaction>(
        AppFailure(
          code: 'sale_ledger_missing',
          message: 'Sale completed but its ledger record could not be found',
        ),
      );
    }

    var effectiveAmount = transfer.amount;
    final advanceEngine = advanceService;
    if (advanceEngine != null) {
      final settlement = await advanceEngine.applyPayment(
        customerId: customer.id,
        amount: transfer.amount,
        // Salafni settlement requires a non-null reference; `_operationId`
        // (below) supplies a stable per-message fallback pattern, but this
        // call's own dedup-by-prefix scheme is unaffected either way — an
        // empty reference here only ever causes a conservative rejection
        // (`settlement_reference_conflict`), never a silent double-credit.
        reference: transfer.reference,
      );
      if (settlement is Failure<AdvancePaymentResult>) {
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.failed,
          action: 'salafni_settlement_failed',
          error: settlement.error,
          transfer: transfer,
          deliveryPhone: destination,
        );
        return Failure<Transaction>(settlement.error);
      }
      final settled = (settlement as Success<AdvancePaymentResult>).value;
      effectiveAmount = settled.remaining;
      if (effectiveAmount.minorUnits == 0) {
        final settlementTransaction = settled.settlementTransaction;
        if (settlementTransaction == null) {
          const failure = AppFailure(
            code: 'salafni_settlement_state_invalid',
            message: 'Salafni was settled but no settlement transaction was returned',
          );
          await _persistTerminalFailure(
            messageId: message.id,
            status: MessageProcessingStatus.failed,
            action: 'salafni_settlement_state_invalid',
            error: failure,
            transfer: transfer,
            deliveryPhone: destination,
          );
          return const Failure<Transaction>(failure);
        }
        await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        return Success<Transaction>(settlementTransaction);
      }
    }

    final matchResult = await _matchActiveCategory(effectiveAmount);
    if (matchResult is Failure<List<CardCategory>>) {
      return Failure<Transaction>(matchResult.error);
    }
    final matches = (matchResult as Success<List<CardCategory>>).value;
    if (matches.isEmpty) {
      final categoryOnly = await _processCategoryAmountsOnly();
      if (categoryOnly) {
        const failure = AppFailure(
          code: 'unmatched_amount_pending',
          message: 'No active card category matches the transfer amount; awaiting review',
        );
        await _persistTerminalFailure(
          messageId: message.id,
          status: MessageProcessingStatus.parsed,
          action: 'transfer_unmatched_amount_pending',
          error: failure,
          transfer: transfer,
          deliveryPhone: destination,
        );
        return const Failure<Transaction>(failure);
      }
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
    final posLookup = posRegistry == null
        ? null
        : await posRegistry!.findByIdentifier(message.sender);
    final posAccount = posLookup is Success<PosAccount?>
        ? posLookup.value
        : null;
    final isPosOrder = posAccount != null &&
        posAccount.status == PointOfSaleStatus.active;
    var effectiveCategory = category;
    if (isPosOrder && categoryCommissionStore != null) {
      final commission = await categoryCommissionStore!.bpsFor(category.id);
      if (commission is Success<int>) {
        effectiveCategory = category.withCommission(commission.value);
      }
    }
    final posCharge = isPosOrder
        ? PosWholesalePricing().unitPrice(
            category: effectiveCategory,
            mode: posAccount!.percentageMode,
          )
        : effectiveCategory.faceValue;
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

    if (!isPosOrder) {
      final credit = await balances.credit(
        customerId: customer.id,
        amount: effectiveAmount,
        reference: transfer.reference.isEmpty ? null : transfer.reference,
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
    }

    final completed = await saleCompleter.completeReservedSale(
      customerId: customer.id,
      cardId: card.id,
      reservationId: reservationId,
      operationId: operationId,
      saleAmount: posCharge,
      allowNegativeBalance: isPosOrder,
    );
    if (completed is Failure<Sale>) {
      await inventoryService.releaseReservation(
        cardId: card.id,
        reservationId: reservationId,
      );
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

    final commitAudit = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'message',
        entityId: message.id,
        action: 'voucher_committed',
        occurredAt: clock.now(),
        payloadJson:
            '{\"operationId\":\"$operationId\",\"cardId\":\"${card.id}\",\"categoryId\":\"${category.id}\",\"reservationId\":\"$reservationId\",\"destination\":\"$destination\"}',
      ),
    );
    if (commitAudit is Failure<void>) {
      await _persistTerminalFailure(
        messageId: message.id,
        status: MessageProcessingStatus.failed,
        action: 'voucher_commit_state_persist_failed',
        error: commitAudit.error,
        transfer: transfer,
        deliveryPhone: destination,
      );
      return Failure<Transaction>(commitAudit.error);
    }

    // Mark sending before the native SMS call so recovery/worker sees an
    // in-flight delivery and can re-attempt quickly if the first send fails.
    await messages.updateStatus(message.id, MessageProcessingStatus.sending);
    final body =
        cardDeliverySmsBody(serialNumber: card.serialNumber, secretCode: card.secretCode);
    final sent = await sender.send(destination: destination, body: body);
    if (sent is Failure<void>) {
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: message.id,
          action: 'sms_delivery_failed',
          occurredAt: clock.now(),
          payloadJson:
              '{\"operationId\":\"$operationId\",\"cardId\":\"${card.id}\",\"categoryId\":\"${category.id}\",\"reservationId\":\"$reservationId\",\"destination\":\"$destination\",\"error\":\"${sent.error.code}\"}',
        ),
      );
      // Sale/voucher already committed — do not reverse. Leave status failed so
      // MessageDeliveryWorker retries within seconds.
      await messages.updateStatus(message.id, MessageProcessingStatus.failed);
      final ledgerOnFail =
          await transactionRepo.findByReference('sale-op:$operationId');
      if (ledgerOnFail is Success<Transaction?> && ledgerOnFail.value != null) {
        return Success<Transaction>(ledgerOnFail.value!);
      }
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
            '{\"operationId\":\"$operationId\",\"cardId\":\"${card.id}\",\"categoryId\":\"${category.id}\",\"reservationId\":\"$reservationId\",\"destination\":\"$destination\"}',
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

    final ledger = await transactionRepo.findByReference('sale-op:$operationId');
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



  Future<Result<List<CardCategory>>> _matchActiveCategory(Money amount) async {
    final categoriesRepo = categories!;
    final now = clock.now();
    final stale = _categoryCache == null ||
        _categoryCacheAt == null ||
        now.difference(_categoryCacheAt!) > _categoryCacheTtl;
    if (stale) {
      final all = await categoriesRepo.listAll();
      if (all is Failure<List<CardCategory>>) {
        return Failure(all.error);
      }
      _categoryCache = (all as Success<List<CardCategory>>).value;
      _categoryCacheAt = now;
    }
    final matches = _categoryCache!
        .where(
          (category) =>
              category.isActive &&
              category.faceValue.currencyCode == amount.currencyCode &&
              category.faceValue.minorUnits == amount.minorUnits,
        )
        .toList(growable: false);
    return Success(matches);
  }

  bool _canAutoProvision(ParsedTransfer transfer) {
    if (transfer.identifierType != TransferIdentifierType.phone) return false;
    final value = transfer.customerIdentifier.trim();
    if (value.isEmpty) return false;
    return value.length >= 7 && RegExp(r'^[0-9+\s-]+$').hasMatch(value);
  }

  Future<Result<Customer>> _autoProvisionCustomer(ParsedTransfer transfer) async {
    final service = customerService;
    if (service == null) {
      return const Failure(
        AppFailure(code: 'customer_service_unavailable', message: 'Customer service not wired'),
      );
    }
    final phone = transfer.customerIdentifier.trim();
    // Contacts decide identity: in phonebook => full customer with name;
    // otherwise provisional ledger-only account.
    var displayName = phone;
    var status = CustomerStatus.provisional;
    final match = await contactDirectory?.findByPhone(phone);
    if (match != null && match.displayName.trim().isNotEmpty) {
      displayName = match.displayName.trim();
      status = CustomerStatus.active;
    }
    final created = await service.create(
      displayName: displayName,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
      status: status,
    );
    if (created is Success<Customer>) return created;
    if (created is Failure<Customer> &&
        created.error.code == 'duplicate_identifier') {
      final existing = await customers.findByIdentifier(phone);
      if (existing is Success<Customer?> && existing.value != null) {
        return Success(existing.value!);
      }
    }
    return Failure(created is Failure<Customer> ? created.error : const AppFailure(
      code: 'auto_provision_failed',
      message: 'Could not auto-create customer from transfer phone',
    ));
  }

  String _operationId(ParsedTransfer transfer) {
    final ref = transfer.reference.trim();
    return ref.isNotEmpty ? ref : 'message:${transfer.messageId}';
  }

  Future<Result<_DeliveryState?>> _deliveryState(String messageId) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return Failure<_DeliveryState?>(logs.error);
    final entries = (logs as Success<List<AuditLog>>)
        .value
        .where((log) =>
            log.action == 'sms_delivery_succeeded' ||
            log.action == 'voucher_committed')
        .toList(growable: false);
    if (entries.isEmpty) return const Success<_DeliveryState?>(null);
    final payload = entries.last.payloadJson ?? '';
    final cardId = _field(payload, 'cardId');
    final reservationId = _field(payload, 'reservationId');
    final categoryId = _field(payload, 'categoryId');
    if (cardId == null || reservationId == null || categoryId == null) {
      return const Failure<_DeliveryState?>(
        AppFailure(
          code: 'delivery_state_invalid',
          message: 'Persisted SMS delivery state is invalid',
        ),
      );
    }
    return Success<_DeliveryState?>(
      _DeliveryState(
        cardId: cardId,
        reservationId: reservationId,
        categoryId: categoryId,
      ),
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
    final match = RegExp('\"$name\":\"([^\"]*)\"').firstMatch(payload);
    return match?.group(1);
  }

  Future<bool> _processCategoryAmountsOnly() async {
    final s = settings;
    if (s == null) return SettingDefaults.processCategoryAmountsOnly;
    final result = await s.find(SettingKeys.processCategoryAmountsOnly);
    if (result is! Success<AppSetting?>) {
      return SettingDefaults.processCategoryAmountsOnly;
    }
    return SettingBool.read(
      result.value?.value,
      defaultValue: SettingDefaults.processCategoryAmountsOnly,
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
            '{\"code\":\"${error.code}\",\"reference\":\"${transfer.reference}\",\"operationId\":\"${_operationId(transfer)}\",\"identifierType\":\"${transfer.identifierType.name}\",\"identifier\":\"${transfer.customerIdentifier}\",\"deliveryPhone\":\"${deliveryPhone ?? ''}\"}',
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
