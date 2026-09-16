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

/// Bottom navigation: dashboard | reports | offers | accounts | cards
/// Uses [IndexedStack] so tab state is preserved (no flicker).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _ids = <String>[
    'dashboard',
    'reports',
    'offers',
    'accounts',
    'cards',
  ];

  static const _titles = <String, String>{
    'dashboard': 'لوحة التحكم',
    'reports': 'التقارير',
    'offers': 'العروض',
    'accounts': 'الحسابات',
    'cards': 'الكروت',
  };

  int _index = 0;
  bool _permissionsStarted = false;

  late final List<Widget> _pages = [
    DashboardScreen(onNavigateToTab: _goToId),
    const ReportsScreen(),
    const OffersScreen(),
    const CustomersScreen(),
    const InventoryScreen(),
  ];

  String get _currentId => _ids[_index];

  void _goToId(String id) {
    final i = _ids.indexOf(id);
    if (i < 0 || i == _index) return;
    setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _permissionsStarted) return;
      _permissionsStarted = true;
      PermissionsOnboarding.maybeRun(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Dashboard and cards use their own headers (match Z Net video).
    final hideAppBar = _currentId == 'dashboard' || _currentId == 'cards';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F9),
      appBar: hideAppBar
          ? null
          : AppBar(
              title: Text(_titles[_currentId] ?? 'NET'),
            ),
      body: SafeArea(
        top: hideAppBar,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: _pages,
        ),
      ),
      floatingActionButton: _currentId == 'dashboard'
          ? FloatingActionButton(
              onPressed: () {
                QuickActionsSheet.show(
                  context,
                  onDirectSale: () => AppRoutes.openDirectSale(context),
                  onPosAccounts: () => AppRoutes.openWalletsAndPos(context),
                  onAddCustomer: () => _goToId('accounts'),
                );
              },
              tooltip: 'إجراءات سريعة',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: KayanBottomNav(
        currentId: _currentId,
        onSelect: _goToId,
      ),
    );
  }
}
