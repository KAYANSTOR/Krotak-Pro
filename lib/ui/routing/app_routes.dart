import 'package:flutter/material.dart';

import '../screens/customer_detail_screen.dart';
import '../screens/direct_sale_screen.dart';
import '../screens/help_center_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transactions_log_screen.dart';
import '../screens/wallets_pos_screen.dart';

/// Central navigation helpers — keeps HomeShell free of ad-hoc MaterialPageRoutes.
abstract final class AppRoutes {
  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  static Future<void> openSettings(BuildContext context) {
    return push(context, const _Subpage(title: 'الإعدادات', child: SettingsScreen()));
  }

  static Future<void> openHelp(BuildContext context) {
    return push(context, const HelpCenterScreen());
  }

  static Future<void> openCustomerDetail(BuildContext context, String customerId) {
    return push(context, CustomerDetailScreen(customerId: customerId));
  }

  static Future<void> openDirectSale(BuildContext context) {
    return push(context, const DirectSaleScreen());
  }

  static Future<void> openTransactionsLog(BuildContext context) {
    return push(context, const TransactionsLogScreen());
  }

  static Future<void> openWalletsAndPos(BuildContext context) {
    return push(context, const WalletsPosScreen());
  }
}

class _Subpage extends StatelessWidget {
  const _Subpage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}
