import 'package:flutter/material.dart';

import 'routing/app_routes.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/reports_screen.dart';
import 'widgets/kayan_bottom_nav.dart';

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_route] ?? 'NET'),
          actions: [
            if (_route == 'dashboard')
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => AppRoutes.openSettings(context),
              ),
          ],
        ),
        body: _pageFor(_route),
        bottomNavigationBar: KayanBottomNav(
          currentId: _route,
          onSelect: (id) => setState(() => _route = id),
        ),
      ),
    );
  }
}
