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
///
/// Pages are created lazily on first visit. This avoids surfacing runtime
/// failures from inactive tabs while the visible tab is rendering. State is
/// preserved after a tab has been visited once.
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
    // Dashboard and cards use their own headers (match Z Net video).
    final hideAppBar = _currentId == 'dashboard' || _currentId == 'cards';
    final children = <Widget>[
      for (var i = 0; i < _pages.length; i++)
        i == _index
            ? _pageForIndex(i)
            : (_pages[i] ?? const SizedBox.shrink()),
    ];

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
