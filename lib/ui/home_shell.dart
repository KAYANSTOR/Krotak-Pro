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

/// Shell with bottom navigation matching the product video tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _ids = ['dashboard', 'reports', 'offers', 'accounts', 'cards'];

  static const _titles = <String, String>{
    'dashboard': 'لوحة التحكم',
    'reports': 'التقارير',
    'offers': 'العروض',
    'accounts': 'الحسابات',
    'cards': 'الكروت',
  };

  static const _icons = <String, IconData>{
    'dashboard': Icons.space_dashboard_rounded,
    'reports': Icons.insights_rounded,
    'offers': Icons.local_offer_rounded,
    'accounts': Icons.groups_rounded,
    'cards': Icons.style_rounded,
  };

  int _index = 0;
  bool _permissionsStarted = false;
  late final List<Widget?> _pages;

  String get _currentId => _ids[_index];

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(_ids.length, null, growable: false);
    _pages[0] = DashboardScreen(onNavigateToTab: _goToId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _permissionsStarted) return;
      _permissionsStarted = true;
      PermissionsOnboarding.maybeRun(context);
    });
  }

  Widget _pageForIndex(int index) {
    final existing = _pages[index];
    if (existing != null) return existing;

    final page = switch (index) {
      0 => DashboardScreen(onNavigateToTab: _goToId),
      1 => const ReportsScreen(),
      2 => const OffersScreen(),
      3 => const CustomersScreen(),
      4 => const InventoryScreen(),
      _ => const SizedBox.shrink(),
    };
    _pages[index] = page;
    return page;
  }

  void _goToId(String id) {
    final i = _ids.indexOf(id);
    if (i < 0 || i == _index) return;
    setState(() {
      _index = i;
      _pageForIndex(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hideAppBar = _currentId == 'dashboard' || _currentId == 'cards';
    final children = <Widget>[
      for (var i = 0; i < _pages.length; i++)
        i == _index
            ? _pageForIndex(i)
            : (_pages[i] ?? const SizedBox.shrink()),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: hideAppBar
          ? null
          : AppBar(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icons[_currentId] ?? Icons.apps_rounded, color: scheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    _titles[_currentId] ?? 'NET',
                    style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
      body: SafeArea(
        top: hideAppBar,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: children,
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
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: KayanBottomNav(
        currentId: _currentId,
        onSelect: _goToId,
      ),
    );
  }
}
