import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/async_views.dart';
import 'package:net_app/ui/widgets/net/net_alert_banner.dart';
import 'package:net_app/ui/widgets/net/net_balance_card.dart';
import 'package:net_app/ui/widgets/net/net_dashboard_header.dart';
import 'package:net_app/ui/widgets/net/net_metric_card.dart';
import 'package:net_app/ui/widgets/net/net_quick_action_card.dart';
import 'package:net_app/ui/widgets/net/net_recent_transaction_card.dart';
import 'package:net_app/ui/widgets/net/net_section_header.dart';

Widget _wrap(
  Widget child, {
  ThemeMode mode = ThemeMode.light,
  TextDirection direction = TextDirection.rtl,
}) {
  return MaterialApp(
    theme: buildKayanLightTheme(),
    darkTheme: buildKayanDarkTheme(),
    themeMode: mode,
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('NetDashboardHeader shows title and subtitle', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetDashboardHeader(title: 'NET', subtitle: 'ترخيص: active')),
    );
    expect(find.text('NET'), findsOneWidget);
    expect(find.textContaining('ترخيص'), findsOneWidget);
  });

  testWidgets('NetDashboardHeader settings callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetDashboardHeader(title: 'NET', onSettings: () => tapped = true)),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(tapped, isTrue);
  });

  testWidgets('NetAlertBanner shows message and invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetAlertBanner(message: 'تنبيه اختبار', onTap: () => tapped = true)),
    );
    expect(find.text('تنبيه اختبار'), findsOneWidget);
    await tester.tap(find.text('تنبيه اختبار'));
    expect(tapped, isTrue);
  });

  testWidgets('NetBalanceCard shows formatted amount and counts', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetBalanceCard(balanceMinor: 150050, accountsCount: 7, availableCards: 12)),
    );
    expect(find.textContaining('1500.5'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('أرصدة العملاء'), findsOneWidget);
  });

  testWidgets('NetMetricCard shows title value subtitle', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetMetricCard(title: 'مبيعات اليوم', value: '100 ر.ي', subtitle: '3 عملية', icon: Icons.today_outlined)),
    );
    expect(find.text('مبيعات اليوم'), findsOneWidget);
    expect(find.text('100 ر.ي'), findsOneWidget);
    expect(find.text('3 عملية'), findsOneWidget);
  });

  testWidgets('NetQuickActionCard invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetQuickActionCard(label: 'بيع مباشر', icon: Icons.point_of_sale_outlined, onTap: () => tapped = true)),
    );
    await tester.tap(find.text('بيع مباشر'));
    expect(tapped, isTrue);
  });

  testWidgets('NetRecentTransactionCard shows type amount status', (tester) async {
    final tx = Transaction(
      id: 'tx1',
      type: TransactionType.deposit,
      status: TransactionStatus.completed,
      amount: const Money(minorUnits: 200000, currencyCode: 'YER'),
      customerId: 'c1',
      reference: 'REF-1',
      createdAt: DateTime(2026, 9, 11),
    );
    await tester.pumpWidget(_wrap(NetRecentTransactionCard(transaction: tx)));
    expect(find.textContaining('deposit'), findsOneWidget);
    expect(find.textContaining('2000'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('REF-1'), findsOneWidget);
  });

  testWidgets('NetDashboardHeader RTL layout', (tester) async {
    await tester.pumpWidget(_wrap(const NetDashboardHeader(title: 'NET', subtitle: 'RTL'), direction: TextDirection.rtl));
    final dir = tester.widget<Directionality>(find.byType(Directionality).last);
    expect(dir.textDirection, TextDirection.rtl);
    expect(find.text('NET'), findsOneWidget);
  });

  testWidgets('NetMetricCard dark theme renders', (tester) async {
    await tester.pumpWidget(_wrap(const NetMetricCard(title: 'مبيعات', value: '0 ر.ي'), mode: ThemeMode.dark));
    expect(find.text('مبيعات'), findsOneWidget);
    expect(find.text('0 ر.ي'), findsOneWidget);
  });

  testWidgets('NetAlertBanner RTL', (tester) async {
    await tester.pumpWidget(_wrap(const NetAlertBanner(message: 'تنبيه'), direction: TextDirection.rtl));
    expect(find.text('تنبيه'), findsOneWidget);
  });

  testWidgets('AsyncLoadingView shows custom message', (tester) async {
    await tester.pumpWidget(_wrap(const AsyncLoadingView(message: 'تحميل مخصص')));
    expect(find.text('تحميل مخصص'), findsOneWidget);
  });

  testWidgets('NetSectionHeader action callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetSectionHeader(title: 'آخر العمليات', actionLabel: 'الكل', onAction: () => tapped = true)),
    );
    await tester.tap(find.text('الكل'));
    expect(tapped, isTrue);
  });
}

Widget _wrap(
  Widget child, {
  ThemeMode mode = ThemeMode.light,
  TextDirection direction = TextDirection.rtl,
}) {
  return MaterialApp(
    theme: buildKayanLightTheme(),
    darkTheme: buildKayanDarkTheme(),
    themeMode: mode,
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  );
}
