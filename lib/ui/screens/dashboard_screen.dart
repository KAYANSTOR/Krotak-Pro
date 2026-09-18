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
import '../widgets/net/net_metric_card.dart';
import '../widgets/net/net_recent_transaction_card.dart';
import '../widgets/net/net_service_tile.dart';
import '../widgets/net/net_section_header.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_transaction_detail_sheet.dart';

/// لوحة التحكم — مطابقة بصرية وسلوكية لفيديو Z Net (المرحلة 1).
///
/// البيانات تُقرأ من نفس الخدمات والمستودعات كما قبل التحديث البصري؛
/// التغييرات محصورة في العرض والتنسيق والحركة.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onNavigateToTab,
    this.refreshSignal,
    this.onMutated,
  });

  final ValueChanged<String>? onNavigateToTab;

  /// Bumped by the shell when another screen mutates data this dashboard shows.
  final ValueListenable<int>? refreshSignal;

  /// Called after this screen performs a mutation (direct sale, POS settlement,
  /// customer creation) so the shell can fan out one shared refresh to every
  /// kept-alive tab. Replaces per-screen reloads that left other tabs stale.
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

  /// Last 7 days of completed-sales totals (major units) for the KPI sparkline.
  List<double> _weeklySalesSeries = const [0, 0, 0, 0, 0, 0, 0];

  /// Locally dismissed alert banners (presentation-only state).
  final Set<String> _dismissedAlerts = <String>{};

  static const _attentionStatuses = <MessageProcessingStatus>[
    MessageProcessingStatus.rejected,
    MessageProcessingStatus.received,
    MessageProcessingStatus.parsed,
    MessageProcessingStatus.failed,
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
    final weekStart = dayStart.subtract(const Duration(days: 6));
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
      final thresholdSetting =
          await c.settings.find(SettingKeys.lowStockThreshold);
      final thresholdRaw = thresholdSetting is Success<AppSetting?>
          ? thresholdSetting.value?.value
          : null;
      final threshold = SettingInt.read(
        thresholdRaw,
        defaultValue: SettingDefaults.lowStockThreshold,
      );

      final healthResult = await c.systemHealth.check();

      // Read-only extra query used purely for the KPI trend sparkline.
      final weeklySales = await c.sales.listCompletedBetween(weekStart, now);

      // شريط الاشتراك (عرض فقط) — من الترخيص الفعلي إن وُجد.
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

      final categories = await c.categories.listAll();
      final low = <({String name, int available})>[];
      if (categories is Success<List<domain.CardCategory>>) {
        for (final cat in categories.value.where((e) => e.isActive)) {
          final avail = await c.cards.findAvailableByCategory(cat.id);
          final count =
              avail is Success<List<domain.Card>> ? avail.value.length : 0;
          if (count < threshold) {
            low.add((name: cat.name, available: count));
          }
        }
      }

      var attentionCount = 0;
      var rejectedCount = 0;
      var attentionFailed = false;
      for (final status in _attentionStatuses) {
        final r = await c.messages.listByStatus(status);
        if (r is Success<List<IncomingMessage>>) {
          attentionCount += r.value.length;
          if (status == MessageProcessingStatus.rejected) {
            rejectedCount = r.value.length;
          }
        } else {
          attentionFailed = true;
        }
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

      final weeklySeries = _bucketDailyTotals(weeklySales, weekStart);

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
        _weeklySalesSeries = weeklySeries;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _dateLabel = dateLabel;
        _error = e.toString();
      });
    }
  }

  /// Buckets completed sales into 7 daily totals (major units), oldest first.
  static List<double> _bucketDailyTotals(Result<List<Sale>> result, DateTime start) {
    final totals = List<double>.filled(7, 0);
    if (result is! Success<List<Sale>>) return totals;
    for (final sale in result.value) {
      final local = sale.createdAt.toLocal();
      final index = DateTime(local.year, local.month, local.day)
          .difference(DateTime(start.year, start.month, start.day))
          .inDays;
      if (index < 0 || index > 6) continue;
      totals[index] += sale.amount.minorUnits / 100.0;
    }
    return totals;
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

  /// Shared shell refresh: bump once after a mutation; every tab listening to
  /// the signal reloads exactly once (no double reload of this dashboard).
  void _notifyMutation() {
    if (!mounted) return;
    widget.onMutated?.call();
    if (widget.refreshSignal == null) {
      // Standalone usage (no shell): keep the old self-reload behaviour.
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

  Future<void> _openWalletsAndPos() async {
    await AppRoutes.openWalletsAndPos(context);
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

  /// Groups recent transactions by calendar day, newest first.
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
              // العنوان الرئيسي هو اسم الشبكة المحفوظ في الإعدادات — بلا سطر
              // تحية (صباح/مساء الخير) كما طُلب.
              showGreeting: false,
              dateLabel: _dateLabel.isEmpty
                  ? formatArabicDashboardDate(DateTime.now())
                  : _dateLabel,
              onSettings: _openSettings,
              onHelp: _openHelp,
              onNotifications: _openAttentionMessages,
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

            // ── حالة معالجة الرسائل + المرفوضة (مطابق للفيديو) ──
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

            // ── الخدمات: 4 كروت كبيرة 2×2 (اثنان وتحتهم اثنان) ──
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
                  onTap: _openWalletsAndPos,
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

            // ── مبيعات اليوم / الشهر (تحت الخدمات) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.sm,
                NetSpacing.lg,
                NetSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NetMetricCard(
                      title: 'مبيعات اليوم',
                      value: formatMoneyMinor(_dailySalesMinor),
                      subtitle: '$_dailyCards كرت',
                      icon: Icons.trending_up_rounded,
                      sparkline: _weeklySalesSeries,
                      onTap: _openDailySalesSheet,
                    ),
                  ),
                  const SizedBox(width: NetSpacing.md),
                  Expanded(
                    child: NetMetricCard(
                      title: 'مبيعات الشهر',
                      value: formatMoneyMinor(_monthlySalesMinor),
                      subtitle: '$_monthlyCards كرت',
                      icon: Icons.calendar_month_outlined,
                      accent: net.info,
                      trailingLabel: 'هذا الشهر',
                      onTap: _openMonthlySalesSheet,
                    ),
                  ),
                ],
              ),
            ),

            NetSectionHeader(
              title: 'العمليات',
              icon: Icons.history_rounded,
              actionLabel: 'الكل',
              onAction: () => AppRoutes.openTransactionsLog(context),
            ),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: NetSpacing.md),
                child: AsyncEmptyView(
                  message: 'لا توجد عمليات حديثة',
                  icon: Icons.receipt_long_outlined,
                  hint: 'ستظهر هنا أول عملية إيداع أو صرف كرت',
                  compact: true,
                ),
              )
            else
              for (final group in groups) ...[
                _DayGroupLabel(label: group.label),
                for (final tx in group.items)
                  NetRecentTransactionCard(
                    transaction: tx,
                    onTap: () => NetTransactionDetailSheet.show(context, tx),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _DayGroupLabel extends StatelessWidget {
  const _DayGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.xl,
        NetSpacing.md,
        NetSpacing.xl,
        NetSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(child: Divider(height: 1, color: palette.border)),
        ],
      ),
    );
  }
}

/// شريط حالة معالجة الرسائل — صف واحد مكثّف كما في الواجهة المرجعية.
class _MessageStatusCard extends StatelessWidget {
  const _MessageStatusCard({
    required this.autoProcessing,
    required this.categoryOnly,
    required this.rejectedCount,
    required this.attentionCount,
    required this.onRejectedTap,
    required this.onAttentionTap,
  });

  final bool autoProcessing;
  final bool categoryOnly;
  final int rejectedCount;
  final int attentionCount;
  final VoidCallback onRejectedTap;
  final VoidCallback onAttentionTap;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final palette = KayanPalette.of(context);
    final statusColor = autoProcessing ? net.success : net.error;
    final statusBg = autoProcessing ? net.successContainer : net.errorContainer;

    return NetSurfaceCard(
      margin: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        6,
        NetSpacing.lg,
        NetSpacing.xs,
      ),
      padding: EdgeInsets.zero,
      onTap: onAttentionTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NetSpacing.md,
          vertical: NetSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: NetRadii.smAll,
              ),
              child: Icon(
                autoProcessing
                    ? Icons.play_circle_filled_rounded
                    : Icons.pause_circle_filled_rounded,
                size: 20,
                color: statusColor,
              ),
            ),
            const SizedBox(width: NetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'حالة معالجة الرسائل',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    autoProcessing
                        ? (categoryOnly
                            ? 'نشطة · مبالغ الفئات المعرفة فقط'
                            : 'نشطة · جميع مبالغ الرسائل')
                        : 'متوقفة · لن تُعالج الرسائل الواردة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NetSpacing.sm),
            if (rejectedCount > 0)
              _CountPill(
                label: '$rejectedCount مرفوضة',
                color: net.rejected,
                background: net.rejectedContainer,
              )
            else if (attentionCount > 0)
              _CountPill(
                label: '$attentionCount معلّقة',
                color: net.warning,
                background: net.warningContainer,
              )
            else
              _CountPill(
                label: 'لا أخطاء',
                color: net.success,
                background: net.successContainer,
              ),
            const SizedBox(width: NetSpacing.xs),
            InkWell(
              onTap: onRejectedTap,
              borderRadius: NetRadii.pillAll,
              child: Padding(
                padding: const EdgeInsets.all(NetSpacing.xs),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: NetSizes.iconSm,
                  color: palette.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.sm,
        vertical: NetSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: NetRadii.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
