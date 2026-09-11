import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/clock.dart';
import '../core/id_generator.dart';
import '../data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate;
import '../data/database/database_provider.dart';
import '../data/database/drift_unit_of_work.dart';
import '../data/repositories/local_repositories.dart';
import '../domain/entities/message.dart';
import '../domain/services/local_account_merge_service.dart';
import '../domain/services/local_backup_service.dart';
import '../domain/services/local_message_recovery_service.dart';
import '../domain/services/local_settlement_service.dart';
import '../domain/services/local_card_inventory_service.dart';
import '../domain/services/local_catalog_services.dart';
import '../domain/services/local_customer_balance_service.dart';
import '../domain/services/local_customer_service.dart';
import '../domain/services/local_license_service.dart';
import '../domain/services/local_message_parser.dart';
import '../domain/services/local_sale_service.dart';
import '../domain/services/local_transfer_processor.dart';
import '../domain/services/services.dart';
import '../platform/sms_bridge.dart';
import 'incoming_sms_handler.dart';

/// Simple composition root. Keeps widgets free of construction logic.
final class AppContainer {
  AppContainer._({
    required this.database,
    required this.customers,
    required this.wallets,
    required this.pointsOfSale,
    required this.categories,
    required this.cards,
    required this.messages,
    required this.transferTemplates,
    required this.transactions,
    required this.sales,
    required this.auditLogs,
    required this.licenses,
    required this.settings,
    required this.unitOfWork,
    required this.customerService,
    required this.balanceService,
    required this.catalogService,
    required this.walletCatalog,
    required this.posCatalog,
    required this.inventoryService,
    required this.saleService,
    required this.messageParser,
    required this.transferProcessor,
    required this.licenseService,
    required this.backupService,
    required this.mergeService,
    required this.settlementService,
    required this.recoveryService,
    required this.smsBridge,
    required this.smsHandler,
    required this.clock,
    required this.ids,
  });

  final AppDatabase database;
  final LocalCustomerRepository customers;
  final LocalWalletRepository wallets;
  final LocalPointOfSaleRepository pointsOfSale;
  final LocalCardCategoryRepository categories;
  final LocalCardRepository cards;
  final LocalMessageRepository messages;
  final LocalTransferTemplateRepository transferTemplates;
  final LocalTransactionRepository transactions;
  final LocalSaleRepository sales;
  final LocalAuditLogRepository auditLogs;
  final LocalLicenseRepository licenses;
  final LocalSettingsRepository settings;
  final DriftUnitOfWork unitOfWork;

  final CustomerService customerService;
  final CustomerBalanceService balanceService;
  final CardCatalogService catalogService;
  final LocalWalletCatalogService walletCatalog;
  final LocalPointOfSaleCatalogService posCatalog;
  final CardInventoryService inventoryService;
  final SaleService saleService;
  final MessageParser messageParser;
  final TransferProcessor transferProcessor;
  final LocalLicenseService licenseService;
  final LocalBackupService backupService;
  final LocalAccountMergeService mergeService;
  final LocalSettlementService settlementService;
  final LocalMessageRecoveryService recoveryService;
  final SmsBridge smsBridge;
  final IncomingSmsHandler smsHandler;
  final Clock clock;
  final IdGenerator ids;

  static Future<AppContainer> bootstrap({
    List<TransferTemplate> templates = const [],
  }) async {
    final database = await openAppDatabase();
    final clock = SystemClock();
    final ids = RandomIdGenerator();
    final uow = DriftUnitOfWork(database);

    final customers = LocalCustomerRepository(database);
    final wallets = LocalWalletRepository(database);
    final pointsOfSale = LocalPointOfSaleRepository(database);
    final categories = LocalCardCategoryRepository(database);
    final cards = LocalCardRepository(database);
    final messages = LocalMessageRepository(database);
    final transferTemplates = LocalTransferTemplateRepository(database);
    final transactions = LocalTransactionRepository(database);
    final sales = LocalSaleRepository(database);
    final auditLogs = LocalAuditLogRepository(database);
    final licenses = LocalLicenseRepository(database);
    final settings = LocalSettingsRepository(database);

    final balanceService = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );

    final customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );

    final walletCatalog = LocalWalletCatalogService(
      wallets: wallets,
      auditLogs: auditLogs,
      clock: clock,
      ids: ids,
    );
    final posCatalog = LocalPointOfSaleCatalogService(
      pointsOfSale: pointsOfSale,
      auditLogs: auditLogs,
      clock: clock,
      ids: ids,
    );

    final catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );

    final inventoryService = LocalCardInventoryService(
      categories: categories,
      cards: cards,
      unitOfWork: uow,
    );

    final saleService = LocalSaleService(
      customers: customers,
      categories: categories,
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balanceService,
      inventory: inventoryService,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );

    final parser = LocalMessageParser(templates: templates);
    final processor = LocalTransferProcessor(
      messages: messages,
      customers: customers,
      balances: balanceService,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );

    final licenseService = LocalLicenseService(
      licenses: licenses,
      clock: clock,
    );

    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docs.path, 'backups'));
    final backupService = LocalBackupService(
      settings: settings,
      clock: clock,
      ids: ids,
      backupDirectory: backupDir,
    );

    final smsBridge = SmsBridge();
    final smsHandler = IncomingSmsHandler(
      bridge: smsBridge,
      messages: messages,
      parser: parser,
      processor: processor,
      ids: ids,
    );

    
    final mergeService = LocalAccountMergeService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    final settlementService = LocalSettlementService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    final recoveryService = LocalMessageRecoveryService(
      messages: messages,
      parser: parser,
      processor: processor,
    );

    return AppContainer._(
      database: database,
      customers: customers,
      wallets: wallets,
      pointsOfSale: pointsOfSale,
      categories: categories,
      cards: cards,
      messages: messages,
      transferTemplates: transferTemplates,
      transactions: transactions,
      sales: sales,
      auditLogs: auditLogs,
      licenses: licenses,
      settings: settings,
      unitOfWork: uow,
      customerService: customerService,
      balanceService: balanceService,
      catalogService: catalogService,
      walletCatalog: walletCatalog,
      posCatalog: posCatalog,
      inventoryService: inventoryService,
      saleService: saleService,
      messageParser: parser,
      transferProcessor: processor,
      licenseService: licenseService,
      backupService: backupService,
      mergeService: mergeService,
      settlementService: settlementService,
      recoveryService: recoveryService,
      smsBridge: smsBridge,
      smsHandler: smsHandler,
      clock: clock,
      ids: ids,
    );
  }

  void startBackgroundHandlers() {
    smsHandler.start();
  }

  Future<void> dispose() async {
    smsHandler.stop();
    await database.close();
  }
}
