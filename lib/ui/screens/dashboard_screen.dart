import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/license.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_alert_banner.dart';
import '../widgets/net/net_balance_card.dart';
import '../widgets/net/net_dashboard_header.dart';
import '../widgets/net/net_metric_card.dart';
import '../widgets/net/net_quick_action_card.dart';
import '../widgets/net/net_recent_transaction_card.dart';
import '../widgets/net/net_section_header.dart';

/// Production dashboard — real Domain/Repository data only.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  String _licenseLabel = '—';
  bool _smsOk = false;
  int _customerBalanceMinor = 0;
  int _accountsCount = 0;
  int _availableCards = 0;
  int _dailySalesMinor = 0;
  int _dailyCards = 0;
  int _monthlySalesMinor = 0;
  int _monthlyCards = 0;
  List<Transaction> _recent = const [];

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

    try {
      final license = await c.licenseService.current();
      final sms = await c.smsBridge.hasPermissions();
      final customers = await c.customers.search('');
      final available = await c.cards.listByStatus(domain.CardStatus.available);
      final dailySales = await c.sales.listCompletedBetween(dayStart, now);
      final monthlySales = await c.sales.listCompletedBetween(monthStart, now);
      final recent = await c.transactions.listRecent(limit: 10);

      var outstanding = 0;
      var accounts = 0;
      if (customers is Success<List<Customer>>) {
        accounts = customers.value.where((e) => e.status == CustomerStatus.active).length;
        for (final customer in customers.value) {
          if (customer.status != CustomerStatus.active) continue;
          final bal = await c.balanceService.getBalance(
            customerId: customer.id,
            currencyCode: 'YER',
          );
          if (bal is Success<Money>) {
            outstanding += bal.value.minorUnits;
          }
        }
      }

      int sumSales(Result<List<Sale>> r) {
        if (r is! Success<List<Sale>>) return 0;
        return r.value.fold<int>(0, (a, s) => a + s.amount.minorUnits);
      }

      int countSales(Result<List<Sale>> r) {
        if (r is! Success<List<Sale>>) return 0;
        return r.value.length;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        if (license is Success<License>) {
          _licenseLabel = license.value.status.name;
        } else {
          _licenseLabel = 'غير مفعّل';
        }
        _smsOk = sms;
        _customerBalanceMinor = outstanding;
        _accountsCount = accounts;
        _availableCards = available is Success<List<domain.Card>> ? available.value.length : 0;
        _dailySalesMinor = sumSales(dailySales);
        _dailyCards = countSales(dailySales);
        _monthlySalesMinor = sumSales(monthlySales);
        _monthlyCards = countSales(monthlySales);
        _recent = recent is Success<List<Transaction>> ? recent.value : const [];
        if (customers is Failure ||
            available is Failure ||
            dailySales is Failure ||
            monthlySales is Failure ||
            recent is Failure) {
          _error = 'تعذر تحميل بعض بيانات اللوحة';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String? get _alertMessage {
    if (!_smsOk) return 'إذن SMS غير مفعّل — قد يتوقف استلام التحويلات';
    if (_licenseLabel == 'غير مفعّل' || _licenseLabel == 'expired' || _licenseLabel == 'invalid') {
      return 'الترخيص: $_licenseLabel — راجع الإعدادات للتفعيل';
    }
    if (_error != null) return _error;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(child: AsyncLoadingView(message: 'جاري تحميل اللوحة…'));
    }
    if (_error != null && _accountsCount == 0 && _recent.isEmpty) {
      return SafeArea(child: AsyncErrorView(message: _error!, onRetry: _load));
    }

    final alert = _alertMessage;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            NetDashboardHeader(
              title: 'NET',
              subtitle: 'ترخيص: $_licenseLabel · SMS: ${_smsOk ? 'جاهز' : 'غير مفعّل'}',
              onSettings: () => AppRoutes.openSettings(context),
            ),
            if (alert != null)
              NetAlertBanner(
                message: alert,
                icon: !_smsOk ? Icons.sms_failed_outlined : Icons.warning_amber_outlined,
                onTap: () => AppRoutes.openSettings(context),
              ),
            NetBalanceCard(
              balanceMinor: _customerBalanceMinor,
              accountsCount: _accountsCount,
              availableCards: _availableCards,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: NetMetricCard(title: 'مبيعات اليوم', value: formatMoneyMinor(_dailySalesMinor), subtitle: '$_dailyCards عملية', icon: Icons.today_outlined, onTap: () => AppRoutes.openTransactionsLog(context))),
                    const SizedBox(width: 10),
                    Expanded(child: NetMetricCard(title: 'مبيعات الشهر', value: formatMoneyMinor(_monthlySalesMinor), subtitle: '$_monthlyCards عملية', icon: Icons.calendar_month_outlined, onTap: () => AppRoutes.openTransactionsLog(context))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: NetMetricCard(title: 'كروت متاحة', value: '$_availableCards', subtitle: 'من المخزون', icon: Icons.sim_card_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: NetMetricCard(title: 'الحسابات النشطة', value: '$_accountsCount', subtitle: 'عملاء', icon: Icons.people_outline)),
                  ]),
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
                  NetQuickActionCard(label: 'بيع مباشر', icon: Icons.point_of_sale_outlined, onTap: () => AppRoutes.openDirectSale(context).then((_) => _load())),
                  const SizedBox(width: 10),
                  NetQuickActionCard(label: 'محافظ / POS', icon: Icons.account_balance_wallet_outlined, onTap: () => AppRoutes.openWalletsAndPos(context)),
                  const SizedBox(width: 10),
                  NetQuickActionCard(label: 'سجل العمليات', icon: Icons.receipt_long_outlined, onTap: () => AppRoutes.openTransactionsLog(context)),
                  const SizedBox(width: 10),
                  NetQuickActionCard(label: 'الإعدادات', icon: Icons.settings_outlined, onTap: () => AppRoutes.openSettings(context)),
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
              ..._recent.map((tx) => NetRecentTransactionCard(transaction: tx, onTap: () => AppRoutes.openTransactionsLog(context))),
          ],
        ),
      ),
    );
  }
}
