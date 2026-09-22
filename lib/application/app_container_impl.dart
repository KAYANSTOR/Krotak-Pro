import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/app_brand.dart';
import '../core/clock.dart';
import '../core/id_generator.dart';
import '../core/result.dart';
import '../data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, AppSetting;
import '../data/database/database_provider.dart';
import '../data/database/drift_unit_of_work.dart';
import '../data/repositories/local_repositories.dart';
import '../domain/entities/message.dart';
import '../domain/entities/setting.dart';
import '../domain/services/local_account_merge_service.dart';
import '../data/repositories/local_broadcast_repository.dart';
import '../domain/services/local_advance_service.dart';
import '../domain/services/local_broadcast_service.dart';
import '../domain/services/local_backup_service.dart';
import '../domain/services/local_maintenance_service.dart';
import '../domain/services/local_message_recovery_service.dart';
import '../domain/services/message_delivery_worker.dart';
import '../domain/services/message_pipeline_trace.dart';
import '../domain/services/pos_order_delivery_worker.dart';
import '../domain/services/local_low_stock_alert_service.dart';
import '../domain/services/local_message_retry_service.dart';
import '../domain/services/local_promotion_catalog.dart';
import '../domain/services/local_promotion_progress_service.dart';
import '../domain/services/local_pos_account_registry.dart';
import '../domain/services/local_pos_balance_request_service.dart';
import '../domain/services/local_pos_profile_service.dart';
import '../domain/services/local_pos_daily_summary_service.dart';
import '../domain/services/local_system_health_service.dart';
import '../domain/services/local_voucher_ops_service.dart';
import '../domain/services/pending_attention_alarm_service.dart';
import '../domain/services/pending_message_review_service.dart';
import '../domain/services/local_settlement_service.dart';
import '../domain/services/local_card_inventory_service.dart';
import '../domain/services/local_catalog_services.dart';
import '../domain/services/local_category_commission_store.dart';
import '../domain/services/default_wallet_templates_seeder.dart';
import '../domain/services/default_outbound_templates_seeder.dart';
import '../domain/services/local_customer_balance_service.dart';
import '../domain/services/local_customer_service.dart';
import '../domain/services/local_license_service.dart';
import '../domain/services/local_message_parser.dart';
import '../domain/services/local_payment_source_registry.dart';
import '../domain/services/local_sale_service.dart';
import '../domain/services/local_transfer_processor.dart';
import '../domain/services/payment_source_guard.dart';
import '../domain/services/unified_payment_event_engine.dart';
import '../domain/services/services.dart';
import '../platform/native_message_sender.dart';
import '../platform/notification_bridge.dart';
import '../platform/stock_alert_bridge.dart';
import '../platform/sms_bridge.dart';
import '../platform/contact_picker_bridge.dart';
import '../platform/system_diagnostics_bridge.dart';
import 'incoming_notification_handler.dart';
import 'incoming_sms_handler.dart';

final class AppContainer {
  AppContainer._({
    required this.database, required this.customers, required this.wallets, required this.pointsOfSale,
    required this.categories, required this.cards, required this.messages, required this.transferTemplates,
    required this.transactions, required this.sales, required this.auditLogs, required this.licenses,
    required this.settings, required this.unitOfWork, required this.customerService, required this.balanceService,
    required this.catalogService, required this.walletCatalog, required this.posCatalog, required this.posRegistry, required this.posProfile,
    required this.inventoryService, required this.saleService, required this.advanceService, required this.broadcastService,
    required this.promotions, required this.promotionProgress, required this.systemHealth, required this.voucherOps,
    required this.pendingAlarm, required LocalMessageParser messageParser, required this.transferProcessor,
    required this.licenseService, required this.backupService, required this.maintenanceService, required this.lowStockAlerts, required this.stockAlertNotifier, required this.dailyPosSummary, required this.mergeService, required this.settlementService,
    required this.recoveryService, required this.deliveryWorker, required this.posOrderDeliveryWorker, required this.retryService, required this.pendingReview, required this.smsBridge,
    required this.smsHandler, required this.notificationBridge, required this.notificationSources,
    required this.notificationHandler, required this.clock, required this.ids, required this.themeModeNotifier,
  }) : _messageParser = messageParser;

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
  final LocalPosAccountRegistry posRegistry;

  /// مصدر واحد لملف نقطة البيع: تحقق + إنشاء/تعديل + زرع كتالوج القوالب.
  final LocalPosProfileService posProfile;
  final CardInventoryService inventoryService;
  final SaleService saleService;
  final AdvanceService advanceService;
  final BroadcastService broadcastService;
  final LocalPromotionCatalog promotions;
  final LocalPromotionProgressService promotionProgress;
  final LocalSystemHealthService systemHealth;
  final LocalVoucherOpsService voucherOps;
  final PendingAttentionAlarmService pendingAlarm;
  final LocalMessageParser _messageParser;
  MessageParser get messageParser => _messageParser;
  final TransferProcessor transferProcessor;
  final LocalLicenseService licenseService;
  final LocalBackupService backupService;
  final LocalMaintenanceService maintenanceService;
  final LocalLowStockAlertService lowStockAlerts;
  final NativeStockAlertNotifier stockAlertNotifier;
  final LocalPosDailySummaryService dailyPosSummary;
  final LocalAccountMergeService mergeService;
  final LocalSettlementService settlementService;
  final LocalMessageRecoveryService recoveryService;
  final MessageDeliveryWorker deliveryWorker;
  final PosOrderDeliveryWorker posOrderDeliveryWorker;
  final LocalMessageRetryService retryService;
  final PendingMessageReviewService pendingReview;
  final SmsBridge smsBridge;
  final IncomingSmsHandler smsHandler;
  final NotificationBridge notificationBridge;
  final LocalPaymentSourceRegistry notificationSources;
  final IncomingNotificationHandler notificationHandler;
  final Clock clock;
  final IdGenerator ids;
  final ValueNotifier<ThemeMode> themeModeNotifier;
  Timer? _recoveryTimer;
  bool _recoveryBusy = false;
  bool _dailySummaryBusy = false;
  bool _disposed = false;
  DateTime? _lastStockSyncAt;
  static const Duration _stockSyncInterval = Duration(seconds: 30);

  Future<Result<void>> reloadTemplates() async {
    final listed = await transferTemplates.listAll();
    if (listed is Failure<List<TransferTemplate>>) return Failure(listed.error);
    _messageParser.replaceTemplates((listed as Success<List<TransferTemplate>>).value);
    return const Success(null);
  }

  static Future<AppContainer> bootstrap({
    List<TransferTemplate> templates = const [],
    AppDatabase? databaseOverride,
    Directory? backupDirectoryOverride,
  }) async {
    final database = databaseOverride ?? await openAppDatabase();
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
    final advanceRepository = LocalAdvanceRepository(transactions: transactions, sales: sales);
    final balanceService = LocalCustomerBalanceService(customers: customers, transactions: transactions, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids, advances: advanceRepository);
    final customerService = LocalCustomerService(customers: customers, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    final walletCatalog = LocalWalletCatalogService(wallets: wallets, auditLogs: auditLogs, settings: settings, clock: clock, ids: ids);
    final posCatalog = LocalPointOfSaleCatalogService(pointsOfSale: pointsOfSale, auditLogs: auditLogs, clock: clock, ids: ids);
    final posRegistry = LocalPosAccountRegistry(settings: settings, clock: clock);
    final categoryCommissionStore = LocalCategoryCommissionStore(settings: settings, clock: clock);
    final catalogService = LocalCardCatalogService(categories: categories, cards: cards, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    final inventoryService = LocalCardInventoryService(categories: categories, cards: cards, unitOfWork: uow);
    final promotions = LocalPromotionCatalog(settings: settings, clock: clock, ids: ids);
    final promotionProgress = LocalPromotionProgressService(promotions: promotions, transactions: transactions);
    final systemHealth = LocalSystemHealthService(bridge: SystemDiagnosticsBridge(), clock: clock);
    final voucherOps = LocalVoucherOpsService(cards: cards, sales: sales, transactions: transactions, balances: balanceService, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    final pendingAlarm = PendingAttentionAlarmService();
    await walletCatalog.ensureDefaultWallets();
    await DefaultWalletTemplatesSeeder(
      wallets: wallets,
      templates: transferTemplates,
      settings: settings,
      clock: clock,
      ids: ids,
    ).seedIfNeeded();
    await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: clock,
    ).seedIfNeeded();

    final listed = await transferTemplates.listAll();
    final live = listed is Success<List<TransferTemplate>> ? listed.value : const <TransferTemplate>[];
    final parser = LocalMessageParser(templates: live.isNotEmpty ? live : templates);
    final smsBridge = SmsBridge();
    final messageSender = NativeMessageSender(smsBridge);
    final saleService = LocalSaleService(customers: customers, categories: categories, cards: cards, sales: sales, transactions: transactions, balances: balanceService, inventory: inventoryService, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids, messageSender: messageSender, settings: settings);
        final broadcastJobs = LocalBroadcastRepository(settings: settings);
    final broadcastService = LocalBroadcastService(customers: customers, jobs: broadcastJobs, settings: settings, auditLogs: auditLogs, messageSender: messageSender, clock: clock, ids: ids, transactions: transactions, posRegistry: posRegistry, sendDelay: Duration.zero);
    final advanceService = LocalAdvanceService(advances: advanceRepository, customers: customers, categories: categories, cards: cards, inventory: inventoryService, transactions: transactions, sales: sales, auditLogs: auditLogs, settings: settings, unitOfWork: uow, messageSender: messageSender, clock: clock, ids: ids, posRegistry: posRegistry);
    final contactDirectory = ContactPickerBridge();
    final processor = LocalTransferProcessor(messages: messages, customers: customers, balances: balanceService, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids, categories: categories, cards: cards, inventory: inventoryService, transactions: transactions, reservedSales: saleService, messageSender: messageSender, settings: settings, advanceService: advanceService, customerService: customerService, contactDirectory: contactDirectory, posRegistry: posRegistry, categoryCommissionStore: categoryCommissionStore, sales: sales);
    final licenseService = LocalLicenseService(licenses: licenses, clock: clock);
    final Directory backupDirectory;
    final File? databaseFile;
    final List<Directory> legacyBackupDirectories;
    if (backupDirectoryOverride != null) {
      backupDirectory = backupDirectoryOverride;
      databaseFile = null;
      legacyBackupDirectories = const <Directory>[];
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      backupDirectory = Directory(p.join(docsDir.path, '${AppBrand.latinName}_Backups'));
      databaseFile = File(p.join(docsDir.path, 'net.sqlite'));
      legacyBackupDirectories = <Directory>[
        Directory(p.join(docsDir.path, 'ZNet_Backups')),
        Directory(p.join(docsDir.path, 'backups')),
      ];
    }
    final backupService = LocalBackupService(
      settings: settings,
      clock: clock,
      ids: ids,
      backupDirectory: backupDirectory,
      databaseFile: databaseFile,
      legacyDirectories: legacyBackupDirectories,
    );
    final maintenanceService = LocalMaintenanceService(
      messages: messages,
      clock: clock,
      database: database,
    );
    // إشعار المخزون الحي على الجهاز: يظهر عند انخفاض أي فئة تحت العتبة ويبقى
    // حتى إعادة تعبئتها (الإلغاء من نفس الخدمة عند ارتفاع المخزون).
    final stockAlertNotifier = NativeStockAlertNotifier();
    final lowStockAlerts = LocalLowStockAlertService(
      settings: settings,
      categories: categories,
      cards: cards,
      clock: clock,
      notifier: stockAlertNotifier,
    );
    final mergeService = LocalAccountMergeService(customers: customers, transactions: transactions, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    final settlementService = LocalSettlementService(customers: customers, transactions: transactions, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    final retryService = LocalMessageRetryService(auditLogs: auditLogs, messages: messages, clock: clock, ids: ids);
    final notificationBridge = NotificationBridge();
    final posProfile = LocalPosProfileService(
      posCatalog: posCatalog,
      posRegistry: posRegistry,
      pointsOfSale: pointsOfSale,
      customers: customers,
      customerService: customerService,
      templates: transferTemplates,
    );
    final notificationSources = LocalPaymentSourceRegistry(settings: settings, clock: clock);
    final sourceGuard = PaymentSourceGuard(wallets: wallets, templates: transferTemplates, notificationSources: notificationSources, posAccounts: posRegistry);
    final posBalanceRequests = LocalPosBalanceRequestService(posRegistry: posRegistry, balances: balanceService, settings: settings, auditLogs: auditLogs, messageSender: messageSender, clock: clock, ids: ids);
    final dailyPosSummary = LocalPosDailySummaryService(
      posRegistry: posRegistry,
      transactions: transactions,
      balances: balanceService,
      settings: settings,
      auditLogs: auditLogs,
      messageSender: messageSender,
      clock: clock,
      ids: ids,
    );
    final pipelineMetrics = MessagePipelineMetrics(auditLogs: auditLogs, clock: clock, ids: ids);
    final smsEngine = UnifiedPaymentEventEngine(messages: messages, parser: parser, processor: processor, ids: ids, settings: settings, sourceGuard: sourceGuard, posBalanceRequestService: posBalanceRequests, metrics: pipelineMetrics);
    final notificationEngine = UnifiedPaymentEventEngine(messages: messages, parser: parser, processor: processor, ids: ids, settings: settings, sourceGuard: sourceGuard, posBalanceRequestService: posBalanceRequests, metrics: pipelineMetrics);
    final recoveryService = LocalMessageRecoveryService(messages: messages, parser: parser, processor: processor, sourceGuard: sourceGuard, retryService: retryService, settings: settings, auditLogs: auditLogs);
    final deliveryWorker = MessageDeliveryWorker(messages: messages, auditLogs: auditLogs, cards: cards, messageSender: messageSender, retryService: retryService, clock: clock, ids: ids, metrics: pipelineMetrics);
    final posOrderDeliveryWorker = PosOrderDeliveryWorker(messages: messages, auditLogs: auditLogs, cards: cards, settings: settings, posRegistry: posRegistry, messageSender: messageSender, retryService: retryService, clock: clock, ids: ids);
    final pendingReview = PendingMessageReviewService(messages: messages, parser: parser, customers: customers, customerService: customerService, balances: balanceService, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids, sourceGuard: sourceGuard);
    final smsHandler = IncomingSmsHandler(
      bridge: smsBridge,
      messages: messages,
      parser: parser,
      processor: processor,
      ids: ids,
      settings: settings,
      advanceService: advanceService,
      engine: smsEngine,
      sourceGuard: sourceGuard,
      onAfterPayment: () => Future.wait([
        deliveryWorker.tick(),
        posOrderDeliveryWorker.tick(),
      ]).then((_) {}),
    );
    final notificationHandler = IncomingNotificationHandler(bridge: notificationBridge, sources: notificationSources, engine: notificationEngine);

    ThemeMode theme = ThemeMode.system;
    final themeSetting = await settings.find(SettingKeys.themeMode);
    if (themeSetting is Success<AppSetting?>) {
      switch ((themeSetting.value?.value ?? 'system').toLowerCase()) {
        case 'dark': theme = ThemeMode.dark;
        case 'light': theme = ThemeMode.light;
        default: theme = ThemeMode.system;
      }
    }

    return AppContainer._(database: database, customers: customers, wallets: wallets, pointsOfSale: pointsOfSale, categories: categories, cards: cards, messages: messages, transferTemplates: transferTemplates, transactions: transactions, sales: sales, auditLogs: auditLogs, licenses: licenses, settings: settings, unitOfWork: uow, customerService: customerService, balanceService: balanceService, catalogService: catalogService, walletCatalog: walletCatalog, posCatalog: posCatalog, posRegistry: posRegistry, posProfile: posProfile, inventoryService: inventoryService, saleService: saleService, advanceService: advanceService, broadcastService: broadcastService, promotions: promotions, promotionProgress: promotionProgress, systemHealth: systemHealth, voucherOps: voucherOps, pendingAlarm: pendingAlarm, messageParser: parser, transferProcessor: processor, licenseService: licenseService, backupService: backupService, maintenanceService: maintenanceService, lowStockAlerts: lowStockAlerts, stockAlertNotifier: stockAlertNotifier, dailyPosSummary: dailyPosSummary, mergeService: mergeService, settlementService: settlementService, recoveryService: recoveryService, deliveryWorker: deliveryWorker, posOrderDeliveryWorker: posOrderDeliveryWorker, retryService: retryService, pendingReview: pendingReview, smsBridge: smsBridge, smsHandler: smsHandler, notificationBridge: notificationBridge, notificationSources: notificationSources, notificationHandler: notificationHandler, clock: clock, ids: ids, themeModeNotifier: ValueNotifier<ThemeMode>(theme));
  }

  Future<void> startBackgroundHandlers() async {
    smsHandler.start();
    await notificationHandler.start();
    await _runRecovery();
    _recoveryTimer ??= Timer.periodic(const Duration(seconds: 3), (_) => _runRecovery());
  }

  Future<void> runRecoveryPass() => _runRecovery();

  Future<void> kickDeliveryWorker() async {
    if (_disposed) return;
    try {
      await deliveryWorker.tick();
      await posOrderDeliveryWorker.tick();
    } catch (_) {}
  }

  Future<void> _runRecovery() async {
    if (_recoveryBusy || _disposed) return;
    // مزامنة إشعار المخزون الحي مع المخزون الفعلي (مُقيَّدة زمنياً). تُشغَّل حتى
    // أثناء عمل التطبيق في الخلفية، فتنقص الفئة من بيع عبر SMS فيظهر التنبيه،
    // ولا يُلغى إلا بعد إعادة التعبئة فوق العتبة.
    await _runStockAlertSync();
    final enabled = await settings.find(SettingKeys.autoRetryFailedMessages);
    final raw = enabled is Success<AppSetting?> ? enabled.value?.value : null;
    if (!SettingBool.read(raw, defaultValue: SettingDefaults.autoRetryFailedMessages)) {
      try {
        await deliveryWorker.tick();
        await posOrderDeliveryWorker.tick();
      } catch (_) {}
      await _runDailyPosSummary();
      return;
    }
    _recoveryBusy = true;
    try {
      await recoveryService.recoverPending();
      await deliveryWorker.tick();
      await posOrderDeliveryWorker.tick();
      await _runDailyPosSummary();
    } finally {
      _recoveryBusy = false;
      try {
        await settings.save(
          AppSetting(
            key: SettingKeys.lastRecoveryPassAt,
            value: clock.now().toIso8601String(),
            updatedAt: clock.now(),
          ),
        );
      } catch (_) {}
    }
  }

  /// مزامنة تنبيه المخزون كل فترة قصيرة بدل كل دورة استرداد (5 ثوان).
  Future<void> _runStockAlertSync() async {
    if (_disposed) return;
    final now = clock.now();
    final last = _lastStockSyncAt;
    if (last != null && now.difference(last) < _stockSyncInterval) return;
    _lastStockSyncAt = now;
    try {
      await lowStockAlerts.syncDeviceAlert();
    } catch (_) {
      // مزامنة التنبيه لا يجوز أن تُسقط دورة الاسترداد أو معالجة الرسائل.
    }
  }

  Future<void> _runDailyPosSummary() async {
    if (_disposed || _dailySummaryBusy) return;
    _dailySummaryBusy = true;
    try {
      await dailyPosSummary.sendDue();
    } catch (_) {
      // Background summary delivery must never interrupt SMS recovery.
    } finally {
      _dailySummaryBusy = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // لا نُلغي إشعار المخزون هنا: الإشعار الحي مملوك لنظام أندرويد ويبقى ظاهراً
    // للمستخدم حتى تُعبَّأ الفئات فعلياً — انظر [LocalLowStockAlertService].
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    pendingAlarm.dispose();
    smsHandler.stop();
    await notificationHandler.stop();
    await database.close();
  }
}
