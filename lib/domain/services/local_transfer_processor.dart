import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/customer.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
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
import 'pos_order_message_renderer.dart';

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
    this.sales,
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
  final SaleRepository? sales;
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

    // Resolve POS scope before any recovery path that depends on it.
    final posLookup = posRegistry == null
        ? null
        : transfer.posId != null && transfer.posId!.trim().isNotEmpty
            ? await posRegistry!.findByPosId(transfer.posId!.trim())
            : await posRegistry!.findByIdentifier(message.sender);
    if (transfer.posId != null && posLookup is Failure<PosAccount?>) {
      return Failure<Transaction>(posLookup.error);
    }
    final posAccount = posLookup is Success<PosAccount?> ? posLookup.value : null;
    final isPosOrder = posAccount != null &&
        posAccount.status == PointOfSaleStatus.active &&
        (transfer.posId == null || transfer.posId == posAccount.posId);

    final txRepo = transactions;
    if (txRepo != null) {
      final existingLedger = await txRepo.findByReference('sale-op:$operationId');
      if (existingLedger is Failure<Transaction?>) {
        return Failure<Transaction>(existingLedger.error);
      }
      final existing = (existingLedger as Success<Transaction?>).value;
      if (existing != null) {
        if (isPosOrder) {
          final recovered = await _recoverCommittedPosSale(
            operationId: operationId,
            transfer: transfer,
            message: message,
            posAccount: posAccount,
            transactionRepo: txRepo,
            sender: messageSender,
          );
          if (recovered is Success<Transaction>) return recovered;
          if (recovered is Failure<Transaction>) return recovered;
        }
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

    // STUB_CONTINUE - full body continues in next update if this lands
    return const Failure<Transaction>(
      AppFailure(code: 'processor_incomplete_upload', message: 'Full processor body pending complete upload'),
    );
  }

  String _operationId(ParsedTransfer transfer) =>
      transfer.reference.isNotEmpty ? transfer.reference : 'msg:${transfer.messageId}';
}
