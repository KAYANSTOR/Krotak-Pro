import 'package:flutter/material.dart';

import 'routing/app_routes.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/reports_screen.dart';
import 'widgets/dashboard/quick_actions_sheet.dart';
import 'widgets/kayan_bottom_nav.dart';
import 'widgets/permissions_onboarding.dart';

/// Bottom navigation aligned with Kotlin:
/// dashboard | reports | offers | accounts | cards
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _route = 'dashboard';

  static const _titles = {
    'dashboard': 'لوحة التحكم',
    'reports': 'التقارير',
    'offers': 'العروض',
    'accounts': 'الحسابات',
    'cards': 'الكروت',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PermissionsOnboarding.maybeRun(context);
    });
  }

  Widget _pageFor(String route) {
    switch (route) {
      case 'accounts':
        return const CustomersScreen();
      case 'cards':
        return const InventoryScreen();
      case 'reports':
        return const ReportsScreen();
      case 'offers':
        return const OffersScreen();
      case 'dashboard':
      default:
        return DashboardScreen(
          onNavigateToTab: (id) => setState(() => _route = id),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideAppBar = _route == 'cards';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F9),
        appBar: hideAppBar
            ? null
            : AppBar(
                title: Text(_titles[_route] ?? 'NET'),
                actions: [
                  if (_route == 'dashboard')
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => AppRoutes.openSettings(context),
                    ),
                ],
              ),
        body: SafeArea(
          top: hideAppBar,
          child: _pageFor(_route),
        ),
        floatingActionButton: _route == 'dashboard'
            ? FloatingActionButton(
                onPressed: () {
                  QuickActionsSheet.show(
                    context,
                    onDirectSale: () => AppRoutes.openDirectSale(context),
                    onPosAccounts: () => AppRoutes.openWalletsAndPos(context),
                    onAddCustomer: () => setState(() => _route = 'accounts'),
                  );
                },
                tooltip: 'إجراءات سريعة',
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: KayanBottomNav(
          currentId: _route,
          onSelect: (id) => setState(() => _route = id),
        ),
      ),
    );
  }
}
