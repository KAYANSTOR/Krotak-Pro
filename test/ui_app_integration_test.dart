import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory;
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/main.dart';
import 'package:net_app/ui/home_shell.dart';
import 'package:net_app/ui/screens/customers_screen.dart';
import 'package:net_app/ui/screens/dashboard_screen.dart';
import 'package:net_app/ui/screens/inventory_screen.dart';
import 'package:net_app/ui/screens/net_splash_screen.dart';
import 'package:net_app/ui/screens/reports_screen.dart';

/// تكامل واجهة: إقلاع + بيانات مجال + تنقل تبويبات بدون الاعتماد على توقيت رسم النصوص.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppContainer container;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups-ui-integration'),
      templates: const [
        TransferTemplate(
          id: 'tpl-ui-int',
          name: 'تحويل اختبار تكامل',
          pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
          isActive: true,
        ),
      ],
    );
  });

  tearDown(() async {
    await container.dispose();
    await database.close();
  });

  Future<void> seedBusinessData() async {
    final customer = await container.customerService.create(
      displayName: 'عميل التكامل',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '777111222',
    );
    expect(customer, isA<Success<Customer>>());

    final category = await container.catalogService.saveCategory(
      const CardCategory(
        id: 'cat-ui-200',
        name: 'فئة تكامل 200',
        faceValue: Money(minorUnits: 20000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    expect(category, isA<Success<CardCategory>>());

    final imported = await container.catalogService.importCards(
      categoryId: 'cat-ui-200',
      drafts: const [
        CardImportDraft(serialNumber: 'SN-UI-1', secretCode: 'PIN-UI-1'),
        CardImportDraft(serialNumber: 'SN-UI-2', secretCode: 'PIN-UI-2'),
      ],
    );
    expect(imported, isA<Success<int>>());
    expect((imported as Success<int>).value, 2);

    final cardRows = await container.cards.findByCategory('cat-ui-200');
    expect(cardRows, isA<Success<List<Card>>>());
    expect((cardRows as Success<List<Card>>).value, hasLength(2));

    final found = await container.customers.findByIdentifier('777111222');
    expect((found as Success<Customer?>).value?.displayName, 'عميل التكامل');
  }

  Future<void> pumpPastSplash(WidgetTester tester) async {
    await tester.pumpWidget(NetApp(container: container));
    await tester.pump();
    expect(find.byType(NetSplashScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(DashboardScreen), findsOneWidget);
  }

  Future<void> openTab(WidgetTester tester, String navKey) async {
    final finder = find.byKey(ValueKey(navKey));
    expect(finder, findsOneWidget, reason: 'missing $navKey');
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: 'exception opening $navKey');
  }

  testWidgets(
    'integration: splash → primary tabs mount after domain seed',
    (tester) async {
      await seedBusinessData();
      await pumpPastSplash(tester);

      expect(find.byType(DashboardScreen), findsOneWidget);

      await openTab(tester, 'nav-reports');
      expect(find.byType(ReportsScreen), findsOneWidget);

      await openTab(tester, 'nav-accounts');
      expect(find.byType(CustomersScreen), findsOneWidget);

      await openTab(tester, 'nav-cards');
      expect(find.byType(InventoryScreen), findsOneWidget);

      await openTab(tester, 'nav-dashboard');
      expect(find.byType(DashboardScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-quick-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('إجراءات سريعة'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 300));

      final stock = await container.cards.findByCategory('cat-ui-200');
      expect((stock as Success<List<Card>>).value, hasLength(2));
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeShell), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'integration: tab cycle stays exception-free after seed',
    (tester) async {
      await seedBusinessData();
      await pumpPastSplash(tester);

      const cycle = <String>[
        'nav-accounts',
        'nav-cards',
        'nav-reports',
        'nav-dashboard',
        'nav-accounts',
        'nav-cards',
      ];
      for (final key in cycle) {
        await openTab(tester, key);
      }

      expect(find.byType(HomeShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
