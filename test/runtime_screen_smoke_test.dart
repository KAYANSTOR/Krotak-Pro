import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/main.dart';
import 'package:net_app/ui/home_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot and render all primary screens without runtime errors', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
      templates: const [
        TransferTemplate(
          id: 'tpl-test',
          name: 'اختبار',
          pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
          isActive: true,
        ),
      ],
    );

    addTearDown(container.dispose);

    await tester.pumpWidget(NetApp(container: container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'Runtime exception during initial app render');

    const navKeys = <String, String>{
      'الحسابات': 'nav-accounts',
      'التقارير': 'nav-reports',
      'الكروت': 'nav-cards',
      'الرئيسية': 'nav-dashboard',
    };

    for (final entry in navKeys.entries) {
      final finder = find.byKey(ValueKey(entry.value));
      expect(finder, findsOneWidget, reason: 'Primary navigation item missing: ${entry.key}');
      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'Runtime exception while opening ${entry.key}');
    }

    // Center button of the bar opens the quick-actions sheet.
    final quickActions = find.byKey(const ValueKey('nav-quick-actions'));
    expect(quickActions, findsOneWidget);
    await tester.tap(quickActions);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'Runtime exception while opening quick actions');
    expect(find.text('إجراءات سريعة'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HomeShell), findsOneWidget);
  });
}
