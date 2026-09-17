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

Widget _wrap(Widget child) => MaterialApp(
      theme: buildKayanLightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('NetDashboardHeader shows network and date', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetDashboardHeader(networkName: 'Z Net', dateLabel: 'الأحد، 14 سبتمبر')),
    );
    expect(find.text('Z Net'), findsOneWidget);
    expect(find.text('الأحد، 14 سبتمبر'), findsOneWidget);
  });

  testWidgets('NetDashboardHeader settings callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetDashboardHeader(
        networkName: 'Z Net',
        dateLabel: 'اليوم',
        onSettings: () => tapped = true,
      )),
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
    expect(find.textContaining('إجمالي رصيد العملاء'), findsOneWidget);
  });

  testWidgets('NetBalanceCard onTapAccounts and onTapCards fire', (tester) async {
    String? tab;
    await tester.pumpWidget(
      _wrap(
        NetBalanceCard(
          balanceMinor: 0,
          accountsCount: 3,
          availableCards: 5,
          onTapAccounts: () => tab = 'accounts',
          onTapCards: () => tab = 'cards',
        ),
      ),
    );
    await tester.tap(find.text('الحسابات'));
    expect(tab, 'accounts');
    await tester.tap(find.text('كروت متوفرة'));
    expect(tab, 'cards');
  });

  testWidgets('NetMetricCard onTap callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        NetMetricCard(
          title: 'الحسابات النشطة',
          value: '4',
          subtitle: 'عملاء',
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.text('الحسابات النشطة'));
    expect(tapped, isTrue);
  });

  testWidgets('NetMetricCard shows title value subtitle', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetMetricCard(title: 'كروت متاحة', value: '9', subtitle: 'وحدة')),
    );
    expect(find.text('كروت متاحة'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('وحدة'), findsOneWidget);
  });

  testWidgets('NetQuickActionCard invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetQuickActionCard(
        label: 'بيع مباشر',
        icon: Icons.point_of_sale,
        onTap: () => tapped = true,
      )),
    );
    await tester.tap(find.text('بيع مباشر'));
    expect(tapped, isTrue);
  });

  testWidgets('NetRecentTransactionCard shows type amount status', (tester) async {
    final transaction = Transaction(
      id: 'tx-1',
      type: TransactionType.sale,
      status: TransactionStatus.completed,
      amount: const Money(minorUnits: 20000, currencyCode: 'YER'),
      createdAt: DateTime(2026, 9, 14, 12),
      reference: 'ref-1',
    );
    await tester.pumpWidget(_wrap(NetRecentTransactionCard(transaction: transaction)));
    expect(find.textContaining('sale'), findsOneWidget);
    expect(find.textContaining('200'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('NetDashboardHeader RTL layout', (tester) async {
    await tester.pumpWidget(
      _wrap(const NetDashboardHeader(networkName: 'شبكتي', dateLabel: 'اليوم')),
    );
    final direction = tester.widget<Directionality>(find.byType(Directionality).first);
    expect(direction.textDirection, TextDirection.rtl);
  });

  testWidgets('NetMetricCard dark theme renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        darkTheme: buildKayanLightTheme(),
        themeMode: ThemeMode.dark,
        home: const NetMetricCard(title: 'اختبار', value: '1'),
      ),
    );
    expect(find.text('اختبار'), findsOneWidget);
  });

  testWidgets('NetAlertBanner RTL', (tester) async {
    await tester.pumpWidget(_wrap(const NetAlertBanner(message: 'RTL')));
    final direction = tester.widget<Directionality>(find.byType(Directionality).first);
    expect(direction.textDirection, TextDirection.rtl);
  });

  testWidgets('AsyncLoadingView shows custom message', (tester) async {
    await tester.pumpWidget(_wrap(const AsyncLoadingView(message: 'جارٍ التحميل')));
    expect(find.text('جارٍ التحميل'), findsOneWidget);
  });

  testWidgets('NetSectionHeader action callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(NetSectionHeader(
        title: 'اختبار',
        actionLabel: 'عرض الكل',
        onAction: () => tapped = true,
      )),
    );
    await tester.tap(find.text('عرض الكل'));
    expect(tapped, isTrue);
  });
}
