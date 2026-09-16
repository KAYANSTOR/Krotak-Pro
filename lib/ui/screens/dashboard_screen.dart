import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/entities/system_capability.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/dashboard/card_stock_sheet.dart';
import '../widgets/dashboard/sales_period_sheet.dart';
import '../widgets/net/net_alert_banner.dart';
import '../widgets/net/net_balance_card.dart';
import '../widgets/net/net_dashboard_header.dart';
import '../widgets/net/net_metric_card.dart';
import '../widgets/net/net_recent_transaction_card.dart';
import '../widgets/net/net_section_header.dart';

/// لوحة التحكم — مطابقة بصرية وسلوكية لفيديو Z Net (المرحلة 1).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<String>? onNavigateToTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  String _networkName = SettingDefaults.networkName;
  String _dateLabel = '';
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

  static const _attentionStatuses = <MessageProcessingStatus>[
    MessageProcessingStatus.rejected,
    MessageProcessingStatus.received,
    MessageProcessingStatus.parsed,
    MessageProcessingStatus.failed,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkName = networkName;
        _dateLabel = dateLabel;
        _attentionMessagesCount = attentionCount;
        _rejectedCount = rejectedCount;
        _autoProcessing = autoProcessing;
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

  Future<void> _openSettings() async {
    await AppRoutes.openSettings(context);
    if (mounted) await _load();
  }

  Future<void> _openHelp() async {
    await AppRoutes.openHelp(context);
  }

  Future<void> _openAttentionMessages() async {
    await AppRoutes.openAttentionMessages(context);
    if (mounted) await _load();
  }

  Future<void> _openRejectedMessages() async {
    await AppRoutes.openRejectedMessages(context);
    if (mounted) await _load();
  }

  Future<void> _openSystemCheck() async {
    await AppRoutes.openSystemCheck(context);
    if (mounted) await _load();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: AsyncLoadingView(message: 'جاري تحميل اللوحة…'),
      );
    }
    if (_error != null && _accountsCount == 0 && _recent.isEmpty) {
      return SafeArea(child: AsyncErrorView(message: _error!, onRetry: _load));
    }

    final lowStockMessage = _lowStockBannerMessage;
    final healthMessage = _healthBannerMessage;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: KayanColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            NetDashboardHeader(
              networkName: _networkName,
              dateLabel: _dateLabel.isEmpty
                  ? formatArabicDashboardDate(DateTime.now())
                  : _dateLabel,
              onSettings: _openSettings,
              onHelp: _openHelp,
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

            if (healthMessage != null)
              NetAlertBanner(
                message: healthMessage,
                icon: Icons.health_and_safety_outlined,
                onTap: _openSystemCheck,
                style: NetAlertStyle.warning,
              ),

            if (lowStockMessage != null)
              NetAlertBanner(
                message: lowStockMessage,
                icon: Icons.warning_amber_rounded,
                onTap: () => widget.onNavigateToTab?.call('cards'),
                style: NetAlertStyle.danger,
              ),

            NetBalanceCard(
              balanceMinor: _customerBalanceMinor,
              accountsCount: _accountsCount,
              availableCards: _availableCards,
              onTapAccounts: () => widget.onNavigateToTab?.call('accounts'),
              onTapCards: _openCardStockSheet,
            ),

            // ── مبيعات اليوم / الشهر ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: NetMetricCard(
                      title: 'مبيعات اليوم',
                      value: formatMoneyMinor(_dailySalesMinor),
                      subtitle: '$_dailyCards كرت',
                      icon: Icons.trending_up_rounded,
                      onTap: _openDailySalesSheet,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NetMetricCard(
                      title: 'مبيعات الشهر',
                      value: formatMoneyMinor(_monthlySalesMinor),
                      subtitle: '$_monthlyCards كرت',
                      icon: Icons.calendar_month_outlined,
                      onTap: _openMonthlySalesSheet,
                    ),
                  ),
                ],
              ),
            ),

            // ── إجراءات سريعة (شبكة 2×2 كالفيديو) ──
            const NetSectionHeader(title: 'إجراءات سريعة'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [
                  _GridAction(
                    label: 'بيع مباشر يدوي',
                    icon: Icons.add_circle_outline,
                    onTap: () =>
                        AppRoutes.openDirectSale(context).then((_) => _load()),
                  ),
                  _GridAction(
                    label: 'حسابات نقاط البيع',
                    icon: Icons.storefront_outlined,
                    onTap: () => AppRoutes.openWalletsAndPos(context),
                  ),
                  _GridAction(
                    label: 'سجل العمليات',
                    icon: Icons.receipt_long_outlined,
                    onTap: () => AppRoutes.openTransactionsLog(context),
                  ),
                  _GridAction(
                    label: 'فحص النظام',
                    icon: Icons.health_and_safety_outlined,
                    onTap: _openSystemCheck,
                  ),
                ],
              ),
            ),

            NetSectionHeader(
              title: 'آخر العمليات',
              actionLabel: 'الكل',
              onAction: () => AppRoutes.openTransactionsLog(context),
            ),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: AsyncEmptyView(message: 'لا توجد عمليات حديثة'),
              )
            else
              ..._recent.map(
                (tx) => NetRecentTransactionCard(
                  transaction: tx,
                  onTap: () => AppRoutes.openTransactionsLog(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة حالة الرسائل — مطابقة لإطار الفيديو.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KayanColors.borderGray),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'حالة معالجة الرسائل',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: KayanColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          categoryOnly
                              ? 'معالجة مبالغ الفئات المعرفة فقط'
                              : 'معالجة جميع مبالغ الرسائل',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: KayanColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: autoProcessing
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          autoProcessing
                              ? Icons.check_circle
                              : Icons.pause_circle_filled,
                          size: 16,
                          color: autoProcessing
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          autoProcessing ? 'نشطة' : 'متوقفة',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: autoProcessing
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            InkWell(
              onTap: onRejectedTap,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 20,
                      color: KayanColors.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'الرسائل المرفوضة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: KayanColors.textPrimary,
                        ),
                      ),
                    ),
                    if (rejectedCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$rejectedCount أخطاء',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      )
                    else if (attentionCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$attentionCount معلّقة',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: KayanColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridAction extends StatelessWidget {
  const _GridAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KayanColors.borderGray),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KayanColors.lightBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: KayanColors.primary, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KayanColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
