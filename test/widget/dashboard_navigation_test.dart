import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/kayan_bottom_nav.dart';
import 'package:net_app/ui/widgets/net/net_balance_card.dart';
import 'package:net_app/ui/widgets/net/net_metric_card.dart';

/// Dashboard → HomeShell tab navigation (root-cause: no SnackBar substitute).
void main() {
  testWidgets('Balance card accounts/cards chips request correct tabs', (tester) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: NetBalanceCard(
              balanceMinor: 10000,
              accountsCount: 2,
              availableCards: 4,
              onTapAccounts: () => requested = 'accounts',
              onTapCards: () => requested = 'cards',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('الحسابات'));
    expect(requested, 'accounts');
    await tester.tap(find.text('كروت متوفرة'));
    expect(requested, 'cards');
  });

  testWidgets('Metric cards request accounts and cards tabs', (tester) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                NetMetricCard(
                  title: 'كروت متاحة',
                  value: '9',
                  onTap: () => requested = 'cards',
                ),
                NetMetricCard(
                  title: 'الحسابات النشطة',
                  value: '3',
                  onTap: () => requested = 'accounts',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('كروت متاحة'));
    expect(requested, 'cards');
    await tester.tap(find.text('الحسابات النشطة'));
    expect(requested, 'accounts');
  });

  testWidgets('KayanBottomNav invokes onSelect with correct ids', (tester) async {
    String? id;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Scaffold(
          bottomNavigationBar: KayanBottomNav(
            currentId: 'dashboard',
            onSelect: (v) => id = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('الحسابات'));
    expect(id, 'accounts');
    await tester.tap(find.text('الكروت'));
    expect(id, 'cards');
    await tester.tap(find.text('التقارير'));
    expect(id, 'reports');
    await tester.tap(find.text('الرئيسية'));
    expect(id, 'dashboard');
  });

  testWidgets('KayanBottomNav center button opens quick actions', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            bottomNavigationBar: KayanBottomNav(
              currentId: 'dashboard',
              onSelect: (_) {},
              onQuickActions: () => opened = true,
            ),
          ),
        ),
      ),
    );
    final center = find.byKey(const ValueKey('nav-quick-actions'));
    expect(center, findsOneWidget);
    await tester.tap(center);
    expect(opened, isTrue);
  });

  testWidgets('Shell-style tab switch via callback (no SnackBar)', (tester) async {
    var route = 'dashboard';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                appBar: AppBar(title: Text(route)),
                body: NetBalanceCard(
                  balanceMinor: 0,
                  accountsCount: 1,
                  availableCards: 1,
                  onTapAccounts: () => setState(() => route = 'accounts'),
                  onTapCards: () => setState(() => route = 'cards'),
                ),
                bottomNavigationBar: KayanBottomNav(
                  currentId: route,
                  onSelect: (id) => setState(() => route = id),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('dashboard'), findsOneWidget);
    final balanceAccounts = find.descendant(
      of: find.byType(NetBalanceCard),
      matching: find.text('الحسابات'),
    );
    await tester.tap(balanceAccounts);
    await tester.pump();
    expect(find.text('accounts'), findsOneWidget);
    final balanceCards = find.descendant(
      of: find.byType(NetBalanceCard),
      matching: find.text('كروت متوفرة'),
    );
    await tester.tap(balanceCards);
    await tester.pump();
    expect(find.text('cards'), findsOneWidget);
  });
}
