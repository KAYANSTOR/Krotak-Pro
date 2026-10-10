import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/settings/backup_restore_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-4 (D1/D2) — النسخة الاحتياطية تُنسخ إلى مجلد عام ظاهر
/// (`Download/Krotak Pro/`) مع إبقاء النسخة الداخلية، ويُعرض المسار الظاهر
/// وزر «مشاركة النسخة».
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
        'path': 'content://downloads/krotak/Krotak Pro/backup.krt',
        'uri': 'content://downloads/krotak/Krotak Pro/backup.krt',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  testWidgets('إنشاء نسخة ينسخها لمجلد ظاهر ويعرض المسار وزر المشاركة',
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

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: const BackupRestoreScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.textContaining('إنشاء نسخة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.at(0), 'secret-pass');
    if (fields.evaluate().length > 1) {
      await tester.enterText(fields.at(1), 'secret-pass');
    }
    await tester.pump();

    await tester.tap(find.text('إنشاء النسخة'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(storageCalls, isNotEmpty, reason: 'لم تُنسخ النسخة إلى المجلد الظاهر');
    final call = storageCalls.first;
    expect(call.method, 'saveToDownloads');
    final args = call.arguments as Map;
    expect((args['fileName'] as String).endsWith('.krt'), isTrue);
    expect(args['mimeType'], 'application/octet-stream');

    expect(find.textContaining('المسار الظاهر'), findsOneWidget);
    expect(find.text('مشاركة النسخة'), findsOneWidget);
  });
}
