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
import '../widgets/async_views.dart';
import '../widgets/dashboard/card_stock_sheet.dart';
import '../widgets/dashboard/sales_period_sheet.dart';
import '../widgets/net/net_alert_banner.dart';
import '../widgets/net/net_balance_card.dart';
import '../widgets/net/net_dashboard_header.dart';
import '../widgets/net/net_metric_card.dart';
import '../widgets/net/net_quick_action_card.dart';
import '../widgets/net/net_recent_transaction_card.dart';
import '../widgets/net/net_section_header.dart';

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
  int _customerBalanceMinor = 0;
  int _accountsCount = 0;
  int _availableCards = 0;
  int _dailySalesMinor = 0;
  int _dailyCards = 0;
  int _monthlySalesMinor = 0;
  int _monthlyCards = 0;
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
      final thresholdSetting = await c.settings.find(SettingKeys.lowStockThreshold);
      final thresholdRaw =
          thresholdSetting is Success<AppSetting?> ? thresholdSetting.value?.value : null;
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
          final count = avail is Success<List<domain.Card>> ? avail.value.length : 0;
          if (count < threshold) {
            low.add((name: cat.name, available: count));
          }
        }
      }

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

      var accounts = 0;
      if (customers is Success<List<Customer>>) {
        accounts =
            customers.value.where((e) => e.status == CustomerStatus.active).length;
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
        if (stored != null && stored.isNotEmpty) {
          networkName = stored;
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkName = networkName;
        _dateLabel = dateLabel;
        _attentionMessagesCount = attentionCount;
        _customerBalanceMinor =
            totalBalance is Success<Money> ? totalBalance.value.minorUnits : 0;
        _accountsCount = accounts;
        _availableCards =
            available is Success<List<domain.Card>> ? available.value.length : 0;
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

  Future<void> _openSystemCheck() async {
    await AppRoutes.openSystemCheck(context);
    if (mounted) await _load();
  }

  String? get _attentionBannerMessage {
    final n = _attentionMessagesCount;
    if (n <= 0) return null;
    if (n == 1) return 'لديك رسالة واحدة مرفوضة أو معلّقة';
    return 'لديك $n رسالة مرفوضة أو معلّقة';
  }

  String? get _lowStockBannerMessage {
    if (_lowStock.isEmpty) return null;
    final parts = _lowStock
        .map((e) => 'كرت ${e.name} (${e.available} متبقي)')
        .join('، ');
    return 'تنبيه: مخزون بعض الفئات منخفض! $parts';
  }

  String? get _healthBannerMessage {
    final h = _health;
    if (h == null) return null;
    if (h.level == SystemHealthLevel.ready) return null;
    return h.bannerMessage;
  }

  IconData get _healthBannerIcon {
    final h = _health;
    if (h == null) return Icons.health_and_safety_outlined;
    switch (h.level) {
      case SystemHealthLevel.critical:
        return Icons.error_outline;
      case SystemHealthLevel.warning:
        return Icons.warning_amber_rounded;
      case SystemHealthLevel.ready:
        return Icons.verified_user_outlined;
    }
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

    final attentionMessage = _attentionBannerMessage;
    final lowStockMessage = _lowStockBannerMessage;
    final healthMessage = _healthBannerMessage;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            NetDashboardHeader(
              networkName: _networkName,
              dateLabel: _dateLabel.isEmpty
                  ? formatArabicDashboardDate(DateTime.now())
                  : _dateLabel,
              onSettings: _openSettings,
              onHelp: _openHelp,
            ),
            if (healthMessage != null)
              NetAlertBanner(
                message: healthMessage,
                icon: _healthBannerIcon,
                onTap: _openSystemCheck,
              ),
            if (lowStockMessage != null)
              NetAlertBanner(
                message: lowStockMessage,
                icon: Icons.inventory_2_outlined,
                onTap: () => widget.onNavigateToTab?.call('cards'),
              ),
            if (attentionMessage != null)
              NetAlertBanner(
                message: attentionMessage,
                icon: Icons.mark_email_unread_outlined,
                onTap: _openAttentionMessages,
              ),
            NetBalanceCard(
              balanceMinor: _customerBalanceMinor,
              accountsCount: _accountsCount,
              availableCards: _availableCards,
              onTapAccounts: () => widget.onNavigateToTab?.call('accounts'),
              onTapCards: _openCardStockSheet,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: NetMetricCard(
                          title: 'مبيعات اليوم',
                          value: formatMoneyMinor(_dailySalesMinor),
                          subtitle: '$_dailyCards كرت',
                          icon: Icons.today_outlined,
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: NetMetricCard(
                          title: 'كروت متاحة',
                          value: '$_availableCards',
                          subtitle: 'من المخزون',
                          icon: Icons.sim_card_outlined,
                          onTap: _openCardStockSheet,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NetMetricCard(
                          title: 'الحسابات النشطة',
                          value: '$_accountsCount',
                          subtitle: 'عملاء',
                          icon: Icons.people_outline,
                          onTap: () =>
                              widget.onNavigateToTab?.call('accounts'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const NetSectionHeader(title: 'إجراءات سريعة'),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  NetQuickActionCard(
                    label: 'بيع مباشر',
                    icon: Icons.point_of_sale_outlined,
                    onTap: () =>
                        AppRoutes.openDirectSale(context).then((_) => _load()),
                  ),
                  const SizedBox(width: 10),
                  NetQuickActionCard(
                    label: 'محافظ / POS',
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: () => AppRoutes.openWalletsAndPos(context),
                  ),
                  const SizedBox(width: 10),
                  NetQuickActionCard(
                    label: 'سجل العمليات',
                    icon: Icons.receipt_long_outlined,
                    onTap: () => AppRoutes.openTransactionsLog(context),
                  ),
                  const SizedBox(width: 10),
                  NetQuickActionCard(
                    label: 'فحص النظام',
                    icon: Icons.health_and_safety_outlined,
                    onTap: _openSystemCheck,
                  ),
                  const SizedBox(width: 10),
                  NetQuickActionCard(
                    label: 'الإعدادات',
                    icon: Icons.settings_outlined,
                    onTap: _openSettings,
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
