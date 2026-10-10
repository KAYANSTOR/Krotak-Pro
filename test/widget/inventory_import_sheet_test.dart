import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/domain/entities/card.dart' as domain;
import 'package:net_app/domain/entities/card_import_log.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/card_import_file_reader.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/inventory_import_sheets.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-5 — ورقة «استيراد كروت من ملف»:
/// ثلاثة صفوف بامتدادات مختلفة (منتقي محاكى)، معاينة أرقام،
/// حفظ ذرّي وسجل عملية، ورسالة عربية للملف المرفوض.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppContainer container;
  late List<CardImportFileKind> pickerCalls;

  Uint8List csvBytes(String body) => Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(body),
      ]);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    await container.catalogService.saveCategory(
      const domain.CardCategory(
        id: 'cat-1',
        name: 'فئة الاستيراد',
        faceValue: Money(minorUnits: 1000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    pickerCalls = <CardImportFileKind>[];
  });

  tearDown(() async {
    await container.dispose();
    await database.close();
  });

  Future<void> openSheet(
    WidgetTester tester,
    Future<CardImportPickedFile?> Function(CardImportFileKind kind) picker,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: FilledButton(
                  onPressed: () => showCardImportFileSheet(
                    ctx,
                    categoryId: 'cat-1',
                    categoryName: 'فئة الاستيراد',
                    categories: <domain.CardCategory>[
                      const domain.CardCategory(
                        id: 'cat-1',
                        name: 'فئة الاستيراد',
                        faceValue: Money(minorUnits: 1000, currencyCode: 'YER'),
                        isActive: true,
                      ),
                    ],
                    onDone: () async {},
                    picker: picker,
                  ),
                  child: const Text('فتح الاستيراد'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('فتح الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('تعرض الصفوف الثلاثة وكل صف يفتح امتداده فقط',
      (tester) async {
    await openSheet(tester, (kind) async {
      pickerCalls.add(kind);
      return null;
    });

    expect(find.text('استيراد كروت من ملف'), findsOneWidget);
    expect(find.text('استيراد ملف PDF'), findsOneWidget);
    expect(find.text('استيراد ملف Excel'), findsOneWidget);
    expect(find.text('استيراد ملف CSV'), findsOneWidget);

    await tester.tap(find.text('استيراد ملف PDF'));
    await tester.pump();
    await tester.tap(find.text('استيراد ملف Excel'));
    await tester.pump();
    await tester.tap(find.text('استيراد ملف CSV'));
    await tester.pump();

    expect(pickerCalls, <CardImportFileKind>[
      CardImportFileKind.pdf,
      CardImportFileKind.xlsx,
      CardImportFileKind.csv,
    ]);
    // إلغاء المنتقي لا يكتب أي سجل.
    final logs = await container.cardImportLogs.listRecent();
    expect((logs as Success<List<CardImportLog>>).value, isEmpty);
  });

  testWidgets('CSV: معاينة بأرقام حقيقية ثم استيراد وسجل مطابق',
      (tester) async {
    await openSheet(tester, (kind) async {
      pickerCalls.add(kind);
      return CardImportPickedFile(
        name: 'كروت-المورد.csv',
        bytes: csvBytes('776733907,77330393
8273738,112233'),
      );
    });

    await tester.tap(find.text('استيراد ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pickerCalls, <CardImportFileKind>[CardImportFileKind.csv]);
    expect(find.text('نتيجة المعاينة'), findsOneWidget);
    expect(find.text('المقبول'), findsOneWidget);

    await tester.tap(find.text('استيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final cards = await database.select(database.cards).get();
    expect(cards, hasLength(2));
    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(1));
    expect(logs.single.fileName, 'كروت-المورد.csv');
    expect(logs.single.fileKind, 'csv');
    expect(logs.single.acceptedCount, cards.length);
    expect(logs.single.status, CardImportLogStatus.completed);
  });

  testWidgets('ملف مرفوض: رسالة عربية بلا كروت وسجل فشل',
      (tester) async {
    await openSheet(tester, (kind) async {
      pickerCalls.add(kind);
      return CardImportPickedFile(
        name: 'صورة.csv',
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );
    });

    await tester.tap(find.text('استيراد ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('نوع الملف غير مدعوم'), findsOneWidget);
    expect(find.text('نتيجة المعاينة'), findsNothing);
    expect(await database.select(database.cards).get(), isEmpty);
    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(1));
    expect(logs.single.status, CardImportLogStatus.failed);
    expect(logs.single.failureReason, isNotNull);
  });

  testWidgets('لا نص لاتيني ظاهر في الورقة', (tester) async {
    await openSheet(tester, (kind) async {
      pickerCalls.add(kind);
      return CardImportPickedFile(
        name: 'كروت.csv',
        bytes: csvBytes('X-1,111'),
      );
    });
    await tester.tap(find.text('استيراد ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // امتدادات الملفات أعلام لا تُترجم (القرار الموثّق في decisions-log).
    const allowed = <String>['PDF', 'Excel', 'CSV', 'csv', 'Krotak Pro'];
    final latin = RegExp('[A-Za-z]');
    for (final element in find.byType(Text).evaluate()) {
      var text = (element.widget as Text).data ?? '';
      for (final term in allowed) {
        text = text.replaceAll(term, '');
      }
      expect(latin.hasMatch(text), isFalse, reason: 'نص لاتيني ظاهر: $text');
    }
  });
}
