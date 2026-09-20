import 'package:flutter/material.dart';

import '../screens/customer_detail_screen.dart';
import '../screens/direct_sale_screen.dart';
import '../screens/failed_messages_screen.dart';
import '../screens/help_center_screen.dart';
import '../screens/pending_messages_screen.dart';
import '../screens/rejected_messages_screen.dart';
import '../screens/reports/pos_accounts_ledger_screen.dart';
import '../screens/reports/sales_period_report_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/system_check_screen.dart';
import '../screens/transactions_log_screen.dart';
import '../screens/wallets_pos_screen.dart';

abstract final class AppRoutes {
  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  static Future<void> openSettings(BuildContext context) {
    return push(context, const SettingsScreen());
  }

  static Future<void> openHelp(BuildContext context) => push(context, const HelpCenterScreen());
  static Future<void> openSystemCheck(BuildContext context) => push(context, const SystemCheckScreen());
  static Future<void> openPendingMessages(BuildContext context) => push(context, const PendingMessagesScreen());
  static Future<void> openFailedMessages(BuildContext context) => push(context, const FailedMessagesScreen());
  static Future<void> openAttentionMessages(BuildContext context) => openPendingMessages(context);
  static Future<void> openRejectedMessages(BuildContext context) => push(context, const RejectedMessagesScreen());
  static Future<void> openCustomerDetail(BuildContext context, String customerId) => push(context, CustomerDetailScreen(customerId: customerId));
  static Future<void> openDirectSale(BuildContext context) => push(context, const DirectSaleScreen());
  static Future<void> openTransactionsLog(BuildContext context) => push(context, const TransactionsLogScreen());
  static Future<void> openWalletsAndPos(BuildContext context, {String? focusPosId}) =>
      push(context, WalletsPosScreen(focusPosId: focusPosId));
  static Future<void> openSalesPeriodReport(
    BuildContext context, {
    SalesReportRange range = SalesReportRange.today,
  }) =>
      push(context, SalesPeriodReportScreen(initialRange: range));
  /// حسابات نقاط البيع — كشف التسوية والدفتر (مطابق للفيديو).
  static Future<void> openPosAccountsLedger(BuildContext context) =>
      push(context, const PosAccountsLedgerScreen());
}
