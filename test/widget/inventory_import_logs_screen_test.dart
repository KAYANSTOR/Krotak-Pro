import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/domain/entities/card_import_log.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/inventory_import_logs_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-5 (P1) — شاشة «إدارة ملفات الاستيراد»:
/// الأرقام من جدول `card_import_logs`، والحذف للسجل فقط، وتصدير التقرير ملفًا حقيقيًا.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel('com.kayan.net/storage');
  late AppDatabase database;
  late AppContainer container;
  late List<MethodCall> storageCalls;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    storageCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      storageCalls.add(call);
      return <String, Object?>{
        'path': 'content://downloads/krotak/Exports/تقرير.csv',
        'uri': 'content://downloads/krotak/Exports/تقرير.csv',
      };
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    await container.dispose();
    await database.close();
  });

  CardImportLog log({
    required String id,
    String fileName = 'كروت-المورد.csv',
    CardImportLogStatus status = CardImportLogStatus.completedWithNotes,
    List<CardImportRejection> rejections = const <CardImportRejection>[],
  }) {
    return CardImportLog(
      id: id,
      fileName: fileName,
      fileKind: 'csv',
      status: status,
      totalRows: 10,
      acceptedCount: 8,
      duplicateCount: 1,
      rejectedCount: 1,
      categoryId: 'cat-1',
      categoryName: 'فئة الاستيراد',
      rejections: rejections,
      startedAt: DateTime(2026, 10, 10, 9, 30),
      finishedAt: DateTime(2026, 10, 10, 9, 30, 5),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: const InventoryImportLogsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('الحالة الفارغة عربية وبها زر استيراد', (tester) async {
    await pumpScreen(tester);
    expect(find.text('لا توجد عمليات استيراد بعد'), findsOneWidget);
    expect(find.text('استيراد ملف'), findsOneWidget);
  });

  testWidgets('تعرض العمليات من الجدول بأرقامها', (tester) async {
    await container.cardImportLogs.save(log(id: 'log-1'));
    await container.cardImportLogs.save(
      log(
        id: 'log-2',
        fileName: 'كروت-المورد-قديم.csv',
        status: CardImportLogStatus.failed,
      ),
    );
    await pumpScreen(tester);

    expect(find.text('كروت-المورد.csv'), findsOneWidget);
    expect(find.text('مكتمل مع ملاحظات'), findsOneWidget);
    expect(find.textContaining('المقبول 8'), findsWidgets);
  });

  testWidgets('التفاصيل تعرض الصفوف المرفوضة بأسبابها', (tester) async {
    await container.cardImportLogs.save(
      log(
        id: 'log-1',
        rejections: const <CardImportRejection>[
          CardImportRejection(line: 3, reason: 'سطر 3: يُتوقّع رقم كرت ورمز سري'),
        ],
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.text('كروت-المورد.csv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('الصفوف المرفوضة'), findsOneWidget);
    expect(find.textContaining('يُتوقّع رقم كرت'), findsOneWidget);
  });

  testWidgets('حذف السجل لا يحذف الكروت من المخزون', (tester) async {
    await database.into(database.cards).insert(
          CardsCompanion.insert(
            id: 'card-1',
            categoryId: 'cat-1',
            serialNumber: 'S-1',
            secretCode: 'P-1',
            status: 'available',
          ),
        );
    await container.cardImportLogs.save(log(id: 'log-1'));
    await pumpScreen(tester);

    await tester.tap(find.text('كروت-المورد.csv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('حذف السجل فقط'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('حذف سجل الاستيراد'), findsOneWidget);
    await tester.tap(find.text('حذف السجل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, isEmpty);
    expect(await database.select(database.cards).get(), hasLength(1),
        reason: 'الكروت لا تُحذف مع السجل');
  });

  testWidgets('تصدير تقرير النتائج ينتج ملف CSV عبر قناة التخزين',
      (tester) async {
    await container.cardImportLogs.save(
      log(
        id: 'log-1',
        rejections: const <CardImportRejection>[
          CardImportRejection(line: 5, reason: 'سطر 5: حقول فارغة'),
        ],
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.text('كروت-المورد.csv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('تصدير تقرير النتائج'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(storageCalls, hasLength(1));
    final call = storageCalls.single;
    expect(call.method, 'saveToDownloads');
    final args = call.arguments as Map;
    expect(args['mimeType'], 'text/csv');
    expect(args['subfolder'], 'Exports');
    expect((args['fileName'] as String).endsWith('.csv'), isTrue);
  });
}
