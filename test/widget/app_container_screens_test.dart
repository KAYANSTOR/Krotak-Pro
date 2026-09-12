// Integration-style widget tests that exercise real screens against a real
// `AppContainer` (Drift over `NativeDatabase.memory()`), instead of stubbing
// data out. This closes the gap explicitly called out by the placeholder in
// `test/widget_test.dart` ("full widget tests need AppContainer bootstrap")
// and in `docs/p0-ui-implementation-report.md` / `p1-ui-implementation-report.md`
// ("Widget tests مع AppContainer كامل لكل شاشة").
//
// Each test builds its own in-memory database + AppContainer via
// `AppContainer.forTesting`, seeds it through the real domain services (never
// by poking the database directly), then pumps the actual screen widget
// wrapped in `AppScope` and asserts on what a user would actually see.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction;
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/customers_screen.dart';
import 'package:net_app/ui/screens/dashboard_screen.dart';
import 'package:net_app/ui/screens/inventory_screen.dart';
import 'package:net_app/ui/screens/reports_screen.dart';
import 'package:net_app/ui/screens/transactions_log_screen.dart';
import 'package:net_app/ui/screens/wallets_pos_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/async_views.dart';
import 'package:net_app/ui/widgets/net/net_balance_card.dart';
import 'package:net_app/ui/widgets/net/net_metric_card.dart';

const _smsChannel = MethodChannel('com.kayan.net/sms');

/// Builds a fresh, isolated container per test: in-memory Drift database,
/// deterministic clock/ids. Never touches `path_provider`.
Future<AppContainer> _buildContainer() {
  final database = AppDatabase(NativeDatabase.memory());
  return AppContainer.forTesting(
    database: database,
    clock: FixedClock(DateTime(2026, 1, 15, 10)),
    ids: SequentialIdGenerator(),
  );
}

/// Wraps [child] the way the app does at runtime: a themed `MaterialApp`
/// with an `AppScope` above it, RTL (the app's only supported direction).
Widget _host(AppContainer container, Widget child) {
  return MaterialApp(
    theme: buildKayanLightTheme(),
    home: AppScope(
      container: container,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  // DashboardScreen calls `smsBridge.hasPermissions()` on its first load.
  // Without a handler, `MethodChannel.invokeMethod` throws
  // `MissingPluginException` in the test binding, which the screen's
  // catch-block turns into an error state — not a bug in the screen, just a
  // platform channel a widget test must stub like any other.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_smsChannel, (call) async {
      switch (call.method) {
        case 'hasPermissions':
          return false;
        case 'requestPermissions':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_smsChannel, null);
  });

  group('DashboardScreen', () {
    testWidgets('shows an honest empty state on a fresh database', (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const DashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.text('ترخيص: غير مفعّل · SMS: غير مفعّل'), findsOneWidget);
      expect(
        find.text('إذن SMS غير مفعّل — قد يتوقف استلام التحويلات'),
        findsOneWidget,
      );
      expect(find.text('لا توجد عمليات حديثة'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(NetBalanceCard), matching: find.text('0 ر.ي')),
        findsOneWidget,
      );
    });

    testWidgets(
        'reflects a real customer, balance, sale and stock from the domain layer, '
        'and forwards tab-navigation taps', (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      final customer = await container.customerService.create(
        displayName: 'Ahmad',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733000111',
      );
      final customerId = (customer as Success<Customer>).value.id;

      await container.balanceService.credit(
        customerId: customerId,
        amount: const Money(minorUnits: 150000, currencyCode: 'YER'),
        reference: 'seed-credit-1',
      );

      await container.catalogService.saveCategory(
        const CardCategory(
          id: 'cat-1000',
          name: 'Yemen Mobile 1000',
          faceValue: Money(minorUnits: 100000, currencyCode: 'YER'),
          isActive: true,
        ),
      );
      await container.catalogService.importCards(
        categoryId: 'cat-1000',
        drafts: const [CardImportDraft(serialNumber: 'S-1', secretCode: 'PIN-1')],
      );

      final sale = await container.saleService.sellFromBalance(
        customerId: customerId,
        categoryId: 'cat-1000',
      );
      expect(sale, isA<Success<Sale>>());

      String? requestedTab;
      await tester.pumpWidget(
        _host(
          container,
          DashboardScreen(onNavigateToTab: (id) => requestedTab = id),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);

      // Remaining balance: 150000 (deposit) - 100000 (sale) = 50000 → "500 ر.ي".
      expect(
        find.descendant(of: find.byType(NetBalanceCard), matching: find.text('500 ر.ي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(NetBalanceCard), matching: find.text('1')),
        findsOneWidget, // 1 active account
      );
      expect(
        find.descendant(of: find.byType(NetBalanceCard), matching: find.text('0')),
        findsOneWidget, // the only card in stock was sold
      );

      final dailyMetric = find.widgetWithText(NetMetricCard, 'مبيعات اليوم');
      final monthlyMetric = find.widgetWithText(NetMetricCard, 'مبيعات الشهر');
      final cardsMetric = find.widgetWithText(NetMetricCard, 'كروت متاحة');
      final accountsMetric = find.widgetWithText(NetMetricCard, 'الحسابات النشطة');
      for (final metric in [dailyMetric, monthlyMetric]) {
        expect(find.descendant(of: metric, matching: find.text('1000 ر.ي')), findsOneWidget);
        expect(find.descendant(of: metric, matching: find.text('1 عملية')), findsOneWidget);
      }
      expect(find.descendant(of: cardsMetric, matching: find.text('0')), findsOneWidget);
      expect(find.descendant(of: accountsMetric, matching: find.text('1')), findsOneWidget);

      // Recent transactions list — both entries really persisted, not fixtures.
      expect(find.text('deposit — 1500 ر.ي'), findsOneWidget);
      expect(find.text('sale — 1000 ر.ي'), findsOneWidget);

      // Balance-card chips forward taps to the shell's tab switcher.
      await tester.ensureVisible(find.text('حسابات'));
      await tester.tap(find.text('حسابات'));
      await tester.pump();
      expect(requestedTab, 'accounts');

      await tester.ensureVisible(find.text('كروت متاحة').first);
      await tester.tap(find.text('كروت متاحة').first);
      await tester.pump();
      expect(requestedTab, 'cards');
    });
  });

  group('CustomersScreen', () {
    testWidgets('shows an empty state, then creates and lists a customer end-to-end',
        (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const CustomersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('لا يوجد عملاء'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.person_add_alt_1));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'اسم العميل'), 'أحمد علي');
      await tester.enterText(find.widgetWithText(TextField, 'رقم الهاتف'), '733111222');
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('أحمد علي'), findsOneWidget);
      expect(find.text('لا يوجد عملاء'), findsNothing);

      // The new customer is really persisted, not just held in local state.
      final persisted = await container.customers.search('733111222');
      expect((persisted as Success).value, hasLength(1));
    });
  });

  group('InventoryScreen', () {
    testWidgets('shows an empty categories tab, then creates a category via the UI',
        (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const InventoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('لا توجد فئات'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'فئة جديدة'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'اسم الفئة'), 'فئة تجريبية');
      // Face-value field keeps its default '1000' seed text.
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('فئة تجريبية'), findsOneWidget);
      expect(find.text('1000 ر.ي'), findsOneWidget);
      expect(find.text('لا توجد فئات'), findsNothing);
    });
  });

  group('ReportsScreen', () {
    testWidgets('shows zeroed report tiles on a fresh database without erroring',
        (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const ReportsScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.text('0 ر.ي · 0'), findsNWidgets(2)); // daily + monthly
      expect(find.text('0 مكتملة (آخر 200)'), findsOneWidget);
      expect(find.text('0 رسالة'), findsOneWidget);
      expect(find.text('0 (واردة/محللة/فاشلة)'), findsOneWidget);
    });
  });

  group('TransactionsLogScreen', () {
    testWidgets('shows an empty state, then a real completed deposit', (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const TransactionsLogScreen()));
      await tester.pumpAndSettle();
      expect(find.text('لا عمليات مسجّلة'), findsOneWidget);

      final customer = await container.customerService.create(
        displayName: 'Sara',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733999888',
      );
      await container.balanceService.credit(
        customerId: (customer as Success<Customer>).value.id,
        amount: const Money(minorUnits: 20000, currencyCode: 'YER'),
        reference: 'seed-credit-2',
      );

      await tester.pumpWidget(_host(container, const TransactionsLogScreen()));
      await tester.pumpAndSettle();

      expect(find.text('deposit — 200 ر.ي'), findsOneWidget);
      expect(find.text('لا عمليات مسجّلة'), findsNothing);
    });
  });

  group('WalletsPosScreen', () {
    testWidgets('shows an empty wallets tab, then adds a wallet via the FAB', (tester) async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, const WalletsPosScreen()));
      await tester.pumpAndSettle();

      expect(find.text('لا محافظ'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'الاسم'), 'محفظة الرصيد');
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('محفظة الرصيد'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.text('لا محافظ'), findsNothing);
    });
  });
}
