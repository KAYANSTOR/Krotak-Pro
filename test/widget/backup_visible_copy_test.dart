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

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    // `listBackups` يقرأ نظام الملفات (I/O حقيقي): لا يكتمل داخل الزمن الوهمي
    // للاختبار، فنمنحه حلقة زمن حقيقية قبل فحص الواجهة.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
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
    // حركة إغلاق الحوار تجري بالزمن الوهمي، والإنشاء لا يبدأ إلا بعدها.
    await tester.pump(const Duration(milliseconds: 400));

    // السبب الجذري لفشل هذا الاختبار سابقاً: `pump()` بلا مدة **لا تُقدّم
    // الساعة الوهمية** (لا تنادي `FakeAsync.elapse`)، فأي خطوة تنتظر مؤقّتاً
    // (تنفيذ createBackup أو قراءة الملف) لا تُنفَّذ أبداً، فلا يكتمل الإنشاء
    // ولا تُستدعى قناة التخزين. الإصلاح: الضخّ بمدة موجبة لتقدّم الزمن مع
    // إتاحة زمن حقيقي لـI/O — وليس زيادة مدة الانتظار.
    for (var attempt = 0; attempt < 240; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (storageCalls.isNotEmpty ||
          find.textContaining('تم إنشاء النسخة').evaluate().isNotEmpty ||
          find.textContaining('تعذر').evaluate().isNotEmpty) {
        break;
      }
    }
    // مزيد من الضخ ليُغلق مستقبل قناة التخزين وتُطبَّق `setState` قبل الفحص.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .where((text) => text.isNotEmpty)
        .join(' | ');
    expect(
      storageCalls,
      isNotEmpty,
      reason: 'لم تُنسخ النسخة إلى المجلد الظاهر. نص الواجهة: $visibleText',
    );
    final call = storageCalls.first;
    expect(call.method, 'saveToDownloads');
    final args = call.arguments as Map;
    expect((args['fileName'] as String).endsWith('.krt'), isTrue);
    expect(args['mimeType'], 'application/octet-stream');

    expect(find.textContaining('المسار الظاهر'), findsOneWidget);
    expect(find.text('مشاركة النسخة'), findsOneWidget);
  });
}
