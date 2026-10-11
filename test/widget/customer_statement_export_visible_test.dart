import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/customer_statement_export.dart';

/// 5.3/WP-3/WP-8 — تصدير كشف الحساب: «حفظ نص» و«حفظ صورة» ينتجان ملفًا
/// فعليًا عبر قناة التخزين الظاهرة، لا في مجلد التطبيق غير المرئي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel('com.kayan.net/storage');
  late List<MethodCall> storageCalls;

  setUp(() {
    storageCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      storageCalls.add(call);
      return <String, Object?>{
        'path': 'content://downloads/krotak/Exports/statement',
        'uri': 'content://downloads/krotak/Exports/statement',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  testWidgets('حفظ نص يحفظ ملفًا في مجلد ظاهر عبر قناة التخزين',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCustomerStatementExportSheet(
                    context: ctx,
                    statementText: 'كشف حساب تجريبي',
                    preview: const SizedBox(
                      width: 320,
                      height: 200,
                      child: Text('معاينة الكشف'),
                    ),
                  ),
                  child: const Text('فتح التصدير'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح التصدير'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('تصدير كشف الحساب'), findsOneWidget);

    await tester.tap(find.text('حفظ نص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final textCall = storageCalls.where((c) => c.method == 'saveToDownloads');
    expect(textCall, isNotEmpty, reason: 'لم تُحفظ النسخة النصية في مجلد ظاهر');
    final args = textCall.first.arguments as Map;
    expect(args['mimeType'], 'text/plain');
    expect(args['subfolder'], 'Exports');
  });

  testWidgets('حفظ صورة يحفظ PNG عبر قناة التخزين', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCustomerStatementExportSheet(
                    context: ctx,
                    statementText: 'كشف حساب تجريبي',
                    preview: const SizedBox(
                      width: 320,
                      height: 200,
                      child: Text('معاينة الكشف'),
                    ),
                  ),
                  child: const Text('فتح التصدير'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح التصدير'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('حفظ صورة'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final imageCall =
        storageCalls.where((c) => c.method == 'saveImageToPictures');
    expect(imageCall, isNotEmpty, reason: 'لم تُحفظ صورة الكشف عبر قناة التخزين');
    final args = imageCall.first.arguments as Map;
    expect((args['fileName'] as String).endsWith('.png'), isTrue);
  });
}
