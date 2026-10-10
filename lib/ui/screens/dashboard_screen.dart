import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../core/contact_admin.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/license.dart' as domain;
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/entities/system_capability.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/repositories.dart';
import '../app_scope.dart';
import '../perf/screen_open_trace.dart';
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
///
/// البيانات تُقرأ من نفس الخدمات والمستودعات كما قبل التحديث البصري؛
/// التغييرات محصورة في العرض والتنسيق والحركة.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onNavigateToTab,
    this.refreshSignal,
    this.onMutated,
    this.onAttentionChanged,
  });

  /// عدد الرسائل التي تحتاج تدخلاً — يرفعه الشريط السفلي كشارة تنبيه حية.
  final ValueChanged<int>? onAttentionChanged;

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

  /// Locally dismissed alert banners (presentation-only state).
  final Set<String> _dismissedAlerts = <String>{};
  final List<StreamSubscription<int>> _messageCountSubscriptions =
      <StreamSubscription<int>>[];
  final Map<MessageProcessingStatus, int> _liveMessageCounts =
      <MessageProcessingStatus, int>{};

  // يجب أن تُطابق هذه القائمة تمامًا مصدر `PendingMessageReviewService
  // .listPending()` — هو ما تفتحه أيقونة التنبيهات فعليًا. كانت تشمل
  // `rejected`/`failed` سابقًا فيظهر عدد في الأيقونة لرسائل لا تعرضها
  // الشاشة المفتوحة (لهما بطاقة/شاشة مستقلة أصلًا: `rejectedCount` أدناه
  // و«الرسائل الفاشلة»)، بينما كانت تتجاهل حالة `pending` الصريحة فلا
  // تُحسب أصلًا. التطابق هنا يضمن أن رقم الأيقونة = ما يظهر فعلًا عند فتحها.
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
    for (final subscription in _messageCountSubscriptions) {
      unawaited(subscription.cancel());
    }
    _messageCountSubscriptions.clear();
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
      final accountsResult = await c.customers.countByStatus(CustomerStatus.active);
      final availableResult = await c.cards.countByStatus(domain.CardStatus.available);
      final dailySumResult = await c.sales.sumCompletedBetween(dayStart, now);
      final dailyCountResult = await c.sales.countCompletedBetween(dayStart, now);
      final monthlySumResult = await c.sales.sumCompletedBetween(monthStart, now);
      final monthlyCountResult = await c.sales.countCompletedBetween(monthStart, now);
      final recent = await c.transactions.listRecent(limit: 10);
      final totalBalance =
          await c.balanceService.getTotalOutstanding(currencyCode: 'YER');
      final networkSetting = await c.settings.find(SettingKeys.networkName);
      final autoSetting =
          await c.settings.find(SettingKeys.smsAutoProcessingEnabled);
      final catOnlySetting =
          await c.settings.find(SettingKeys.processCategoryAmountsOnly);
      final healthResult = await c.systemHealth.check();

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

      // مصدر واحد لتنبيه المخزون: نفس الخدمة تحسب الفئات الناقصة وتزامن إشعار
      // أندرويد الحي (يظهر عند النقص ويُلغى فقط بعد إعادة التعبئة فوق العتبة).
      final lowStockAlerts = await c.lowStockAlerts.syncDeviceAlert();
      final low = <({String name, int available})>[
        for (final alert in lowStockAlerts)
          (name: alert.categoryName, available: alert.available),
      ];

      var attentionCount = 0;
      var attentionFailed = false;
      for (final status in _attentionStatuses) {
        final r = await c.messages.countByStatus(status);
        if (r is Success<int>) {
          attentionCount += r.value;
          _liveMessageCounts[status] = r.value;
        } else {
          attentionFailed = true;
        }
      }

      // مستقلة عن عدّاد التنبيهات أعلاه: لها بطاقتها الخاصة (`_rejectedCount`
      // / `onRejectedTap`) ولا تفتحها أيقونة التنبيهات.
      var rejectedCount = 0;
      final rejectedResult =
          await c.messages.countByStatus(MessageProcessingStatus.rejected);
      if (rejectedResult is Success<int>) {
        rejectedCount = rejectedResult.value;
        _liveMessageCounts[MessageProcessingStatus.rejected] = rejectedCount;
      } else {
        attentionFailed = true;
      }

      final accounts = accountsResult is Success<int> ? accountsResult.value : 0;
      final availableCards = availableResult is Success<int> ? availableResult.value : 0;

      int extractInt(Result<int> r) => r is Success<int> ? r.value : 0;

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
        ScreenOpenTrace.instance.markLatestDataReady('dashboard');
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
        _availableCards = availableCards;
        _dailySalesMinor = extractInt(dailySumResult);
        _dailyCards = extractInt(dailyCountResult);
        _monthlySalesMinor = extractInt(monthlySumResult);
        _monthlyCards = extractInt(monthlyCountResult);
        _recent =
            recent is Success<List<Transaction>> ? recent.value : const [];
        _lowStock = low;
        _health = healthResult is Success<SystemHealthSnapshot>
            ? healthResult.value
            : null;
        if (accountsResult is Failure ||
            availableResult is Failure ||
            dailySumResult is Failure ||
            dailyCountResult is Failure ||
            monthlySumResult is Failure ||
            monthlyCountResult is Failure ||
            recent is Failure ||
            totalBalance is Failure ||
            attentionFailed) {
          _error = 'تعذر تحميل بعض بيانات اللوحة';
        }
      });
      // شارة التنبيه في الشريط السفلي: عدد الرسائل المعلّقة/المرفوضة.
      widget.onAttentionChanged?.call(attentionCount);
      _startMessageCountWatches(c.messages);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        ScreenOpenTrace.instance.markLatestDataReady('dashboard');
        _dateLabel = dateLabel;
        _error = e.toString();
      });
    }
  }

  void _startMessageCountWatches(MessageRepository messages) {
    for (final subscription in _messageCountSubscriptions) {
      unawaited(subscription.cancel());
    }
    _messageCountSubscriptions.clear();

    final statuses = <MessageProcessingStatus>[
      ..._attentionStatuses,
      MessageProcessingStatus.rejected,
    ];
    for (final status in statuses) {
      final subscription = messages.watchCountByStatus(status).listen(
        (count) => _onLiveMessageCount(status, count),
        onError: (_, __) {},
      );
      _messageCountSubscriptions.add(subscription);
    }
  }

  void _onLiveMessageCount(MessageProcessingStatus status, int count) {
    if (!mounted) return;
    _liveMessageCounts[status] = count;
    final attentionCount = _attentionStatuses.fold<int>(
      0,
      (total, item) => total + (_liveMessageCounts[item] ?? 0),
    );
    final rejectedCount =
        _liveMessageCounts[MessageProcessingStatus.rejected] ?? 0;
    setState(() {
      _attentionMessagesCount = attentionCount;
      _rejectedCount = rejectedCount;
    });
    widget.onAttentionChanged?.call(attentionCount);
  }

  /// Buckets completed sales into 7 daily totals (major units), oldest first.
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

  void _contactAdmin() => AdminContact.openWhatsApp(context);

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

  /// نقطة البيع في الرئيسية تفتح شاشة نقاط البيع **مباشرة** (كانت تفتح إدارة
  /// المحافظ ونقاط البيع في تبويب المحافظ).
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
              onContactAdmin: _contactAdmin,
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
                  label: 'إعدادات التطبيق',
                  description: 'ضبط الكروت والمحافظ والرسائل',
                  icon: Icons.settings_rounded,
                  onTap: _openSettings,
                ),
              ],
            ),

            // ── المبيعات ──
            NetSectionHeader(
              title: 'المبيعات',
              icon: Icons.bar_chart_rounded,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NetSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: NetMetricCard(
                      label: 'مبيعات اليوم',
                      value: formatMoneyMinor(_dailySalesMinor),
                      subtitle: '$_dailyCards كرت',
                      icon: Icons.today_rounded,
                      onTap: _openDailySalesSheet,
                    ),
                  ),
                  const SizedBox(width: NetSpacing.md),
                  Expanded(
                    child: NetMetricCard(
                      label: 'مبيعات الشهر',
                      value: formatMoneyMinor(_monthlySalesMinor),
                      subtitle: '$_monthlyCards كرت',
                      icon: Icons.calendar_month_rounded,
                      onTap: _openMonthlySalesSheet,
                    ),
                  ),
                ],
              ),
            ),

            // ── آخر العمليات ──
            NetSectionHeader(
              title: 'آخر العمليات',
              icon: Icons.history_rounded,
              actionLabel: 'السجل الكامل',
              onAction: () => AppRoutes.openTransactionsLog(context),
            ),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: NetSpacing.lg),
                child: NetSurfaceCard(
                  child: Text('لا توجد عمليات حديثة'),
                ),
              )
            else
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NetSpacing.lg,
                    NetSpacing.md,
                    NetSpacing.lg,
                    NetSpacing.sm,
                  ),
                  child: Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: net.muted,
                        ),
                  ),
                ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.md,
        NetSpacing.lg,
        0,
      ),
      child: NetSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  autoProcessing
                      ? Icons.play_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: autoProcessing ? net.success : net.warning,
                ),
                const SizedBox(width: NetSpacing.sm),
                Text(
                  autoProcessing ? 'المعالجة الآلية نشطة' : 'المعالجة الآلية متوقفة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (categoryOnly) ...[
              const SizedBox(height: NetSpacing.xs),
              Text(
                'فقط مبالغ الفئات',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: net.muted,
                    ),
              ),
            ],
            const SizedBox(height: NetSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _StatusChip(
                    label: 'تحتاج تدخلًا',
                    count: attentionCount,
                    color: net.warning,
                    onTap: onAttentionTap,
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: _StatusChip(
                    label: 'مرفوضة',
                    count: rejectedCount,
                    color: net.danger,
                    onTap: onRejectedTap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NetRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NetSpacing.md,
          vertical: NetSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(NetRadius.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              '$count',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
