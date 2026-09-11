import 'package:flutter/material.dart';

import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/kayan_bottom_nav.dart';

/// Shell matching Kotlin bottom nav routes:
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
        return const MessagesScreen();
      case 'offers':
        return const SettingsScreen();
      case 'dashboard':
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_route] ?? 'NET'),
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
