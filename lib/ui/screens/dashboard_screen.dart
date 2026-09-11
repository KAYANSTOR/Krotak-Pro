import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/license.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/dashboard/customer_balance_card.dart';
import '../widgets/dashboard/quick_actions_grid.dart';
import '../widgets/dashboard/sales_cards_row.dart';

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

      // Sum outstanding customer balances (active customers, YER)
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
        _availableCards =
            available is Success<List<domain.Card>> ? available.value.length : 0;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AsyncLoadingView();
    if (_error != null && _accountsCount == 0 && _recent.isEmpty) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => AppRoutes.openSettings(context),
                  icon: const Icon(Icons.settings_outlined, color: KayanColors.textPrimary),
                ),
                const Spacer(),
                const Text(
                  'NET',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: KayanColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً بك',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الترخيص: $_licenseLabel',
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: KayanColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _smsOk ? KayanColors.successBackground : KayanColors.warningBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _smsOk ? Icons.check_circle : Icons.warning_amber,
                    color: _smsOk ? KayanColors.success : KayanColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _smsOk ? 'النظام نشط — صلاحيات SMS جاهزة' : 'يلزم تفعيل صلاحيات SMS',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.bold,
                        color: _smsOk ? KayanColors.success : KayanColors.warning,
                      ),
                    ),
                  ),
                  if (!_smsOk)
                    TextButton(
                      onPressed: () async {
                        await AppScope.of(context).smsBridge.requestPermissions();
                        await _load();
                      },
                      child: const Text('تفعيل', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                ],
              ),
            ),
          ),
          CustomerBalanceCard(
            amount: _customerBalanceMinor,
            accounts: _accountsCount,
            cards: _availableCards,
            onCardStockClick: () {},
          ),
          SalesCardsRow(
            dailyAmount: _dailySalesMinor,
            dailyCards: _dailyCards,
            monthlyAmount: _monthlySalesMinor,
            monthlyCards: _monthlyCards,
            onDailyClick: () => AppRoutes.openTransactionsLog(context),
            onMonthlyClick: () => AppRoutes.openTransactionsLog(context),
          ),
          QuickActionsGrid(
            onAction: (id) {
              switch (id) {
                case 'manualDirectSale':
                  AppRoutes.openDirectSale(context).then((_) => _load());
                case 'salesPoints':
                  AppRoutes.openWalletsAndPos(context);
                default:
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'غير متاح في هذا الإصدار: $id',
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  );
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'آخر العمليات',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: KayanColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => AppRoutes.openTransactionsLog(context),
                  child: const Text('الكل', style: TextStyle(fontFamily: 'Tajawal', color: KayanColors.primary)),
                ),
              ],
            ),
          ),
          if (_recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: AsyncEmptyView(message: 'لا توجد عمليات حديثة'),
            )
          else
            ..._recent.map((tx) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(
                  '${tx.type.name} — ${formatMoneyMinor(tx.amount.minorUnits)}',
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                subtitle: Text(
                  tx.reference ?? tx.id,
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                ),
                trailing: Text(
                  tx.status.name,
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                ),
              );
            }),
        ],
      ),
    );
  }
}
