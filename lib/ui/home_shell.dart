import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'routing/app_routes.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/reports_screen.dart';
import 'widgets/dashboard/customer_create_sheet.dart';
import 'widgets/dashboard/quick_actions_sheet.dart';
import 'widgets/kayan_bottom_nav.dart';
import 'widgets/permissions_onboarding.dart';

/// Shell with bottom navigation matching the product video tabs.
///
/// Each tab renders its own [NetTabHeader] so there is exactly one header per
/// screen (no duplicated shell AppBar + in-body title) and no nested Scaffolds.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _ids = ['dashboard', 'reports', 'offers', 'accounts', 'cards'];

  /// Signals the dashboard to reload after a mutation performed elsewhere
  /// (direct sale, POS accounts) without coupling the tabs together.
  final ValueNotifier<int> _dashboardRefresh = ValueNotifier<int>(0);

  int _index = 0;
  bool _permissionsStarted = false;
  late final List<Widget?> _pages;

  String get _currentId => _ids[_index];

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(_ids.length, null, growable: false);
    _pages[0] = _buildDashboard();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _permissionsStarted) return;
      _permissionsStarted = true;
      PermissionsOnboarding.maybeRun(context);
    });
  }

  @override
  void dispose() {
    _dashboardRefresh.dispose();
    super.dispose();
  }

  Widget _buildDashboard() => DashboardScreen(
        onNavigateToTab: _goToId,
        refreshSignal: _dashboardRefresh,
      );

  Widget _pageForIndex(int index) {
    final existing = _pages[index];
    if (existing != null) return existing;

    final page = switch (index) {
      0 => _buildDashboard(),
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
    if (id == 'dashboard') _dashboardRefresh.value++;
  }

  Future<void> _openDirectSale() async {
    await AppRoutes.openDirectSale(context);
    if (mounted) _dashboardRefresh.value++;
  }

  Future<void> _openWalletsAndPos() async {
    await AppRoutes.openWalletsAndPos(context);
    if (mounted) _dashboardRefresh.value++;
  }

  /// Center button of the bottom bar — the same quick actions the dashboard
  /// exposes, so every tab reaches them without extra navigation.
  void _openQuickActions() {
    QuickActionsSheet.show(
      context,
      onDirectSale: _openDirectSale,
      onPosAccounts: _openWalletsAndPos,
      onAddCustomer: () => _goToId('accounts'),
      onCreateCustomer: () async {
        await CustomerCreateSheet.show(context);
        if (mounted) _dashboardRefresh.value++;
      },
      onOffers: () => _goToId('offers'),
      onCards: () => _goToId('cards'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (var i = 0; i < _pages.length; i++)
        i == _index
            ? _pageForIndex(i)
            : (_pages[i] ?? const SizedBox.shrink()),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: children,
        ),
      ),
      bottomNavigationBar: KayanBottomNav(
        currentId: _currentId,
        onSelect: _goToId,
        onQuickActions: _openQuickActions,
      ),
    );
  }
}
