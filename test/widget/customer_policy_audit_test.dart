import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, AuditLog, AppSetting;
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/services/customer_deposit_block.dart';
import 'package:net_app/domain/services/salafni_customer_ceiling.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/customer_detail_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// سياسات العميل من ملفه: كل تغيير يُحفظ ويُسجَّل في Audit (الخطة §10.5 وAC-D3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppContainer container;
  late Customer customer;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups-customer-policy'),
    );
    AppScope.register(container);
    final created = await container.customerService.create(
      displayName: 'عميل السياسات',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733999111',
    );
    customer = (created as Success<Customer>).value;
  });

  tearDown(() async {
    AppScope.unregister(container);
    await container.dispose();
    await database.close();
  });

  /// دفعات إطار ثابتة بدل `pumpAndSettle` حتى لا يتعلّق الاختبار على مؤشر
  /// تحديث أو حركة مستمرة، مع ترك وقت كافٍ لقراءة قاعدة البيانات.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: AppScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: CustomerDetailScreen(customerId: customer.id),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<String>> auditActions() async {
    final rows = await container.auditLogs.findByEntity('customer', customer.id);
    return (rows as Success<List<AuditLog>>)
        .value
        .map((entry) => entry.action)
        .toList(growable: false);
  }

  testWidgets('blocking deposits from the file stores the block and audits it',
      (tester) async {
    await pumpScreen(tester);

    final tile = find.byType(SwitchListTile);
    expect(tile, findsOneWidget);
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    final stored = await container.settings.find(CustomerDepositBlock.key);
    expect(
      CustomerDepositBlock.isBlocked(
        (stored as Success<AppSetting?>).value?.value,
        customer.id,
      ),
      isTrue,
    );
    expect(await auditActions(), contains('deposit_block_updated'));
  });

  testWidgets('saving a salafni ceiling stores the value and audits it',
      (tester) async {
    await pumpScreen(tester);

    final card = find.widgetWithText(ListTile, 'سقف سلفني');
    expect(card, findsOneWidget);
    await tester.ensureVisible(card);
    await settle(tester);
    await tester.tap(card);
    await settle(tester);

    final dialog = find.byType(AlertDialog);
    final field = find.descendant(of: dialog, matching: find.byType(TextField));
    expect(field, findsOneWidget);
    await tester.enterText(field, '500');
    await tester.tap(find.descendant(
      of: dialog,
      matching: find.widgetWithText(FilledButton, 'حفظ'),
    ));
    await settle(tester);

    final stored = await container.settings.find(SalafniCustomerCeiling.key);
    expect(
      SalafniCustomerCeiling.forCustomer(
        (stored as Success<AppSetting?>).value?.value,
        customer.id,
      ),
      50000,
    );
    expect(await auditActions(), contains('salafni_ceiling_updated'));
  });
}
