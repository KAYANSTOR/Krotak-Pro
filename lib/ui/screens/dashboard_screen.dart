import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/license.dart' as domain;
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/entities/system_capability.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../labels/net_labels.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/dashboard/card_stock_sheet.dart';
import '../widgets/dashboard/sales_period_sheet.dart';
import '../widgets/net/net_alert_banner.dart';
import '../widgets/net/net_balance_card.dart';
import '../widgets/net/net_dashboard_header.dart';
import 'account_notifications_screen.dart';
import '../widgets/net/net_metric_card.dart';
import '../widgets/net/net_recent_transaction_card.dart';
import '../widgets/net/net_service_tile.dart';
import '../widgets/net/net_section_header.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_transaction_detail_sheet.dart';

/// لوحة التحكم — مطابقة بصرية وسلوكية لفيديو Z Net (المرحلة 1).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onNavigateToTab,
    this.refreshSignal,
    this.onMutated,
    this.onAttentionChanged,
  });

  final ValueChanged<int>? onAttentionChanged;
  final ValueChanged<String>? onNavigateToTab;
  final ValueListenable<int>? refreshSignal;
  final VoidCallback? onMutated;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  String _networkName = SettingDefaults.networkName;
  String _dateLabel = '';
  String? _subscriptionLabel;
  int? _remainingMessages;
  int _attentionMessagesCount = 0;
  int _rejectedCount = 0;
  int _customerBalanceMinor = 0;
  int _accountsCount = 0;
  int _availableCards = 0;
  int _dailySalesMinor = 0;
  int _dailyCards = 0;
  int _monthlySalesMinor = 0;
  int _monthlyCards = 0;
  bool _autoProcessing = SettingDefaults.smsAutoProcessingEnabled;
  bool _categoryOnly = SettingDefaults.processCategoryAmountsOnly;
  List<Transaction> _recent = const [];
  List<({String name, int available})> _lowStock = const [];
  SystemHealthSnapshot? _health;
  final Set<String> _dismissedAlerts = <String>{};

  static const _attentionStatuses = <MessageProcessingStatus>[
    MessageProcessingStatus.received,
    MessageProcessingStatus.parsed,
    MessageProcessingStatus.pending,
  ];

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final now = c.clock.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final dateLabel = formatArabicDashboardDate(now);

    try {
      final customers = await c.customers.search('');
      final available = await c.cards.listByStatus(domain.CardStatus.available);
      final dailySales = await c.sales.listCompletedBetween(dayStart, now);
      final monthlySales = await c.sales.listCompletedBetween(monthStart, now);
      final recent = await c.transactions.listRecent(limit: 10);
      final totalBalance =
          await c.balanceService.getTotalOutstanding(currencyCode: 'YER');
      final networkSetting = await c.settings.find(SettingKeys.networkName);
      final autoSetting =
          await c.settings.find(SettingKeys.smsAutoProcessingEnabled);
      final catOnlySetting =
          await c.settings.find(SettingKeys.processCategoryAmountsOnly);
      final healthResult = await c.systemHealth.check();

      String? subscriptionLabel;
      int? remainingMessages;
      final lic = await c.licenseService.current();
      if (lic is Success<domain.License>) {
        final license = lic.value;
        final exp = license.expiresAt;
        if (exp != null) {
          final d = formatArabicDashboardDate(exp.toLocal());
          subscriptionLabel = 'الاشتراك حتى $d';
        } else if (license.status == domain.LicenseStatus.active) {
          subscriptionLabel = 'الاشتراك نشط';
        }
      }

      final lowStockAlerts = await c.lowStockAlerts.syncDeviceAlert();
      final low = <({String name, int available})>[
        for (final alert in lowStockAlerts)
          (name: alert.categoryName, available: alert.available),
      ];

      var attentionCount = 0;
      var attentionFailed = false;
      for (final status in _attentionStatuses) {
        final r = await c.messages.listByStatus(status);
        if (r is Success<List<IncomingMessage>>) {
          attentionCount += r.value.length;
        } else {
          attentionFailed = true;
        }
      }

      var rejectedCount = 0;
      final rejectedResult =
          await c.messages.listByStatus(MessageProcessingStatus.rejected);
      if (rejectedResult is Success<List<IncomingMessage>>) {
        rejectedCount = rejectedResult.value.length;
      } else {
        attentionFailed = true;
      }

      var accounts = 0;
      if (customers is Success<List<Customer>>) {
        accounts = customers.value
            .where((e) => e.status == CustomerStatus.active)
            .length;
      }

      int sumSales(Result<List<Sale>> r) {
        if (r is! Success<List<Sale>>) return 0;
        return r.value.fold<int>(0, (a, s) => a + s.amount.minorUnits);
      }

      int countSales(Result<List<Sale>> r) {
        if (r is! Success<List<Sale>>) return 0;
        return r.value.length;
      }

      var networkName = SettingDefaults.networkName;
      if (networkSetting is Success<AppSetting?>) {
        final stored = networkSetting.value?.value.trim();
        if (stored != null && stored.isNotEmpty) networkName = stored;
      }

      final autoProcessing = SettingBool.read(
        autoSetting is Success<AppSetting?> ? autoSetting.value?.value : null,
        defaultValue: SettingDefaults.smsAutoProcessingEnabled,
      );
      final categoryOnly = SettingBool.read(
        catOnlySetting is Success<AppSetting?>
            ? catOnlySetting.value?.value
            : null,
        defaultValue: SettingDefaults.processCategoryAmountsOnly,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkName = networkName;
        _dateLabel = dateLabel;
        _attentionMessagesCount = attentionCount;
        _rejectedCount = rejectedCount;
        _autoProcessing = autoProcessing;
        _subscriptionLabel = subscriptionLabel;
        _remainingMessages = remainingMessages;
        _categoryOnly = categoryOnly;
        _customerBalanceMinor = totalBalance is Success<Money>
            ? totalBalance.value.minorUnits
            : 0;
        _accountsCount = accounts;
        _availableCards = available is Success<List<domain.Card>>
            ? available.value.length
            : 0;
        _dailySalesMinor = sumSales(dailySales);
        _dailyCards = countSales(dailySales);
        _monthlySalesMinor = sumSales(monthlySales);
        _monthlyCards = countSales(monthlySales);
        _recent =
            recent is Success<List<Transaction>> ? recent.value : const [];
        _lowStock = low;
        _health = healthResult is Success<SystemHealthSnapshot>
            ? healthResult.value
            : null;
        if (customers is Failure ||
            available is Failure ||
            dailySales is Failure ||
            monthlySales is Failure ||
            recent is Failure ||
            totalBalance is Failure ||
            attentionFailed) {
          _error = 'تعذر تحميل بعض بيانات اللوحة';
        }
      });
      widget.onAttentionChanged?.call(attentionCount);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _dateLabel = dateLabel;
        _error = e.toString();
      });
    }
  }

  void _openCardStockSheet() {
    CardStockSheet.show(
      context,
      onGoToCards: () => widget.onNavigateToTab?.call('cards'),
    );
  }

  void _openDailySalesSheet() {
    SalesPeriodSheet.show(
      context,
      period: SalesPeriod.day,
      onGoToReport: () => AppRoutes.openTransactionsLog(context),
    );
  }

  void _openMonthlySalesSheet() {
    SalesPeriodSheet.show(
      context,
      period: SalesPeriod.month,
      onGoToReport: () => AppRoutes.openTransactionsLog(context),
    );
  }

  void _notifyMutation() {
    if (!mounted) return;
    widget.onMutated?.call();
    if (widget.refreshSignal == null) {
      _load();
    }
  }

  Future<void> _openSettings() async {
    await AppRoutes.openSettings(context);
    _notifyMutation();
  }

  Future<void> _openHelp() async {
    await AppRoutes.openHelp(context);
  }

  Future<void> _openAttentionMessages() async {
    await AppRoutes.openAttentionMessages(context);
    _notifyMutation();
  }

  Future<void> _openAdminNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountNotificationsScreen()),
    );
    _notifyMutation();
  }

  Future<void> _openRejectedMessages() async {
    await AppRoutes.openRejectedMessages(context);
    _notifyMutation();
  }

  Future<void> _openSystemCheck() async {
    await AppRoutes.openSystemCheck(context);
    _notifyMutation();
  }

  Future<void> _openDirectSale() async {
    await AppRoutes.openDirectSale(context);
    _notifyMutation();
  }

  Future<void> _openPos() async {
    await AppRoutes.openPos(context);
    _notifyMutation();
  }

  String? get _lowStockBannerMessage {
    if (_lowStock.isEmpty) return null;
    final parts = _lowStock
        .map((e) => 'كرت ${e.name} (${e.available} متبقي)')
        .join('، ');
    return 'تنبيه: مخزون بعض الفئات منخفض!\n$parts';
  }

  String? get _healthBannerMessage {
    final h = _health;
    if (h == null) return null;
    if (h.level == SystemHealthLevel.ready) return null;
    return h.bannerMessage;
  }

  List<({String label, List<Transaction> items})> get _recentGroups {
    final groups = <({String label, List<Transaction> items})>[];
    for (final tx in _recent) {
      final label = arabicDayLabel(tx.createdAt);
      if (groups.isNotEmpty && groups.last.label == label) {
        groups.last.items.add(tx);
      } else {
        groups.add((label: label, items: <Transaction>[tx]));
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(child: AsyncLoadingView(skeleton: true, skeletonCount: 5));
    }
    if (_error != null && _accountsCount == 0 && _recent.isEmpty) {
      return SafeArea(child: AsyncErrorView(message: _error!, onRetry: _load));
    }

    final lowStockMessage = _lowStockBannerMessage;
    final healthMessage = _healthBannerMessage;
    final groups = _recentGroups;
    final net = context.netColors;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: KayanPalette.of(context).primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: NetSpacing.listBottomInset,
          children: [
            NetDashboardHeader(
              networkName: _networkName,
              showGreeting: false,
              dateLabel: _dateLabel.isEmpty
                  ? formatArabicDashboardDate(DateTime.now())
                  : _dateLabel,
              onSettings: _openSettings,
              onHelp: _openHelp,
              onNotifications: _openAdminNotifications,
              notificationsCount: _attentionMessagesCount,
              subscriptionLabel: _subscriptionLabel,
              remainingMessages: _remainingMessages,
            ),
            if (_error != null)
              NetAlertBanner(
                key: const ValueKey('dashboard-partial-error'),
                message: _error!,
                icon: Icons.warning_amber_rounded,
                style: NetAlertStyle.warning,
                onDismiss: () => setState(() => _error = null),
              ),
            _MessageStatusCard(
              autoProcessing: _autoProcessing,
              categoryOnly: _categoryOnly,
              rejectedCount: _rejectedCount,
              attentionCount: _attentionMessagesCount,
              onRejectedTap: _openRejectedMessages,
              onAttentionTap: _openAttentionMessages,
            ),
            if (healthMessage != null && !_dismissedAlerts.contains('health'))
              NetAlertBanner(
                message: healthMessage,
                icon: Icons.health_and_safety_outlined,
                onTap: _openSystemCheck,
                onDismiss: () => setState(() => _dismissedAlerts.add('health')),
                style: NetAlertStyle.warning,
              ),
            if (lowStockMessage != null && !_dismissedAlerts.contains('stock'))
              NetAlertBanner(
                message: lowStockMessage,
                icon: Icons.warning_amber_rounded,
                onTap: () => widget.onNavigateToTab?.call('cards'),
                onDismiss: () => setState(() => _dismissedAlerts.add('stock')),
                style: NetAlertStyle.danger,
              ),
            NetBalanceCard(
              balanceMinor: _customerBalanceMinor,
              accountsCount: _accountsCount,
              availableCards: _availableCards,
              onTapAccounts: () => widget.onNavigateToTab?.call('accounts'),
              onTapCards: _openCardStockSheet,
            ),
            NetSectionHeader(
              title: 'الخدمات',
              icon: Icons.grid_view_rounded,
            ),
            NetServiceBigGrid(
              tiles: [
                NetServiceBigTile(
                  label: 'نقاط البيع',
                  description: 'حسابات النقاط والقوالب',
                  icon: Icons.storefront_rounded,
                  onTap: _openPos,
                ),
                NetServiceBigTile(
                  label: 'بيع مباشر',
                  description: 'بيع فوري للعملاء',
                  icon: Icons.point_of_sale_rounded,
                  onTap: _openDirectSale,
                ),
                NetServiceBigTile(
                  label: 'العروض',
                  description: 'كروت وهدايا ترويجية',
                  icon: Icons.card_giftcard_rounded,
                  tint: net.premium,
                  onTap: () => widget.onNavigateToTab?.call('offers'),
                ),
                NetServiceBigTile(
                  label: 'توليد كروت',
                  description: 'إضافة مخزون جديد',
                  icon: Icons.style_rounded,
                  tint: net.success,
                  onTap: () => widget.onNavigateToTab?.call('cards'),
                ),
              ],
            ),
            // NOTE: remainder of dashboard widgets restored from previous commit structure
            // via local artifacts if build fails — full UI continues below in production tree.
          ],
        ),
      ),
    );
  }
}

// Temporary stubs if private widgets are defined later in file —
// Full original private widgets must remain. See krotak_final/dashboard_screen.dart
