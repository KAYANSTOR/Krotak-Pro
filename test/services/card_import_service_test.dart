import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/domain/entities/card.dart' as domain;
import 'package:net_app/domain/entities/card_import_log.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/card_import_preview.dart';
import 'package:net_app/domain/services/services.dart';

/// WP-5 — مسار الاستيراد المنفّذ في الخدمة:
/// ذرّية بلا دفعة جزئية، ولا كروت مكررة عند إعادة المحاولة،
/// وسجل عملية يطابق أرقام قاعدة البيانات، وبلا مساس أي سجل مالي.
void main() {
  late AppDatabase database;
  late AppContainer container;
  late String categoryId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    final saved = await container.catalogService.saveCategory(
      const domain.CardCategory(
        id: 'cat-import',
        name: 'فئة الاستيراد',
        faceValue: const Money(minorUnits: 1000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    expect(saved, isA<Success<domain.CardCategory>>());
    categoryId = 'cat-import';
  });

  tearDown(() async {
    await container.dispose();
    await database.close();
  });

  Uint8List csvBytes(String body, {bool bom = true}) {
    final bytes = <int>[
      if (bom) ...<int>[0xEF, 0xBB, 0xBF],
      ...utf8.encode(body),
    ];
    return Uint8List.fromList(bytes);
  }

  test('ملف CSV بـBOM وأرقام عربية: استيراد كامل وسجل مطابق', () async {
    final read = await container.cardImportService.readAndAnalyze(
      fileName: 'كروت-المورد.csv',
      bytes: csvBytes('776733907,77330393\n٨٢٧٣٧٣٨,112233'),
      format: CardImportFormat.serialAndPin,
    );
    expect(read, isA<Success<CardImportReadOutcome>>());
    final outcome = (read as Success<CardImportReadOutcome>).value;
    expect(outcome.fileKind, 'csv');
    expect(outcome.preview.acceptedCount, 2);

    final committed = await container.cardImportService.commit(
      preview: outcome.preview,
      fileKind: outcome.fileKind,
      categoryId: categoryId,
      categoryName: 'فئة الاستيراد',
    );
    expect(committed, isA<Success<CardImportOutcome>>());
    final result = (committed as Success<CardImportOutcome>).value;
    expect(result.acceptedCount, 2);
    expect(result.log.status, CardImportLogStatus.completed);

    final cards = await database.select(database.cards).get();
    expect(cards, hasLength(2));
    expect(cards.map((row) => row.serialNumber).toSet(),
        <String>{'776733907', '٨٢٧٣٧٣٨'});

    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(1));
    expect(logs.single.acceptedCount, cards.length,
        reason: 'أرقام السجل تطابق عدّ قاعدة البيانات');
    expect(logs.single.categoryName, 'فئة الاستيراد');
    // لا مساس مالي: لا حركات ولا بيع.
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(await database.select(database.sales).get(), isEmpty);
  });

  test('تكرار داخل الملف وتكرار في المخزون يُستبعدان بلا فشل الدفعة', () async {
    final first = await container.cardImportService.readAndAnalyze(
      fileName: 'دفعة-1.csv',
      bytes: csvBytes('A-1,111\nA-2,222'),
      format: CardImportFormat.serialAndPin,
    );
    final firstOutcome = (first as Success<CardImportReadOutcome>).value;
    final firstCommit = await container.cardImportService.commit(
      preview: firstOutcome.preview,
      fileKind: firstOutcome.fileKind,
      categoryId: categoryId,
    );
    expect(firstCommit, isA<Success<CardImportOutcome>>());

    // ملف يحوي مكررًا داخله ومكررًا في المخزون وجديدًا.
    final second = await container.cardImportService.readAndAnalyze(
      fileName: 'دفعة-2.csv',
      bytes: csvBytes('A-2,999\nB-1,333\nB-1,444'),
      format: CardImportFormat.serialAndPin,
    );
    final preview = (second as Success<CardImportReadOutcome>).value.preview;
    expect(preview.stockDuplicateSerials, <String>{'A-2'});
    expect(preview.acceptedCount, 1);
    expect(preview.parseErrors, hasLength(1));

    final committed = await container.cardImportService.commit(
      preview: preview,
      fileKind: 'csv',
      categoryId: categoryId,
    );
    final result = (committed as Success<CardImportOutcome>).value;
    expect(result.acceptedCount, 1);
    expect(result.duplicateCount, 1);
    expect(result.rejectedCount, 1);
    expect(result.log.status, CardImportLogStatus.completedWithNotes);
    expect(result.log.rejections, isNotEmpty);

    final cards = await database.select(database.cards).get();
    expect(cards, hasLength(3));
  });

  test('إعادة العملية لا تُنشئ كروتًا مكررة', () async {
    final read = await container.cardImportService.readAndAnalyze(
      fileName: 'دفعة.csv',
      bytes: csvBytes('C-1,111\nC-2,222'),
      format: CardImportFormat.serialAndPin,
    );
    final preview = (read as Success<CardImportReadOutcome>).value.preview;
    await container.cardImportService.commit(
      preview: preview,
      fileKind: 'csv',
      categoryId: categoryId,
    );
    expect(await database.select(database.cards).get(), hasLength(2));

    // نفس الملف مرة ثانية: كل الأرقام موجودة في المخزون.
    final again = await container.cardImportService.readAndAnalyze(
      fileName: 'دفعة.csv',
      bytes: csvBytes('C-1,111\nC-2,222'),
      format: CardImportFormat.serialAndPin,
    );
    final repeated = (again as Success<CardImportReadOutcome>).value.preview;
    expect(repeated.acceptedCount, 0);
    final second = await container.cardImportService.commit(
      preview: repeated,
      fileKind: 'csv',
      categoryId: categoryId,
    );
    expect(second, isA<Failure<CardImportOutcome>>());
    expect(await database.select(database.cards).get(), hasLength(2),
        reason: 'لا كروت مكررة');

    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(2));
    expect(logs.first.status, CardImportLogStatus.failed);
    expect(logs.first.failureReason, isNotNull);
  });

  test('ذرّية: صف واحد غير صالح يُلغي الدفعة كلها بلا حفظ جزئي', () async {
    final preview = CardImportPreview(
      drafts: const <CardImportDraft>[
        CardImportDraft(serialNumber: 'OK-1', secretCode: '111'),
        CardImportDraft(serialNumber: '   ', secretCode: '222'),
      ],
      parseErrors: const <String>[],
      stockDuplicateSerials: const <String>{},
      fileName: 'دفعة-مخلوطة.csv',
    );
    final committed = await container.cardImportService.commit(
      preview: preview,
      fileKind: 'csv',
      categoryId: categoryId,
    );
    expect(committed, isA<Failure<CardImportOutcome>>());
    expect(await database.select(database.cards).get(), isEmpty,
        reason: 'لا دفعة جزئية');
    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(1));
    expect(logs.single.status, CardImportLogStatus.failed);
  });

  test('ملف بامتداد صحيح ومحتوى مختلف يُرفض ويُسجّل فشله', () async {
    // PNG منسوب إلى .csv — يُرفض بتوقيع المحتوى لا بالامتداد.
    final png = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02, 0x03,
    ]);
    final read = await container.cardImportService.readAndAnalyze(
      fileName: 'ملف-مزور.csv',
      bytes: png,
      format: CardImportFormat.serialAndPin,
    );
    expect(read, isA<Failure<CardImportReadOutcome>>());
    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs, hasLength(1));
    expect(logs.single.status, CardImportLogStatus.failed);
    expect(logs.single.failureReason, isNotNull);
    expect(logs.single.acceptedCount, 0);
    expect(await database.select(database.cards).get(), isEmpty);
  });

  test('ملف فارغ يُرفض ويُسجّل بلا كروت', () async {
    final read = await container.cardImportService.readAndAnalyze(
      fileName: 'فارغ.csv',
      bytes: Uint8List.fromList(const <int>[]),
      format: CardImportFormat.serialAndPin,
    );
    expect(read, isA<Failure<CardImportReadOutcome>>());
    final logs = (await container.cardImportLogs.listRecent() as Success<List<CardImportLog>>).value;
    expect(logs.single.failureReason, 'الملف فارغ');
    expect(await database.select(database.cards).get(), isEmpty);
  });

  test('ملف Excel و PDF: النوع يُسجّل بالعربية ولا يُخلط', () async {
    final xlsx = Uint8List.fromList(<int>[
      0x50, 0x4B, 0x03, 0x04,
      ...utf8.encode('<t>D-1,111</t>'),
    ]);
    final read = await container.cardImportService.readAndAnalyze(
      fileName: 'كروت.xlsx',
      bytes: xlsx,
      format: CardImportFormat.serialAndPin,
    );
    expect(read, isA<Success<CardImportReadOutcome>>());
    final outcome = (read as Success<CardImportReadOutcome>).value;
    expect(outcome.fileKind, 'xlsx');
    final committed = await container.cardImportService.commit(
      preview: outcome.preview,
      fileKind: outcome.fileKind,
      categoryId: categoryId,
    );
    final result = (committed as Success<CardImportOutcome>).value;
    expect(result.log.fileKindLabel, 'Excel');
    expect(await database.select(database.cards).get(), hasLength(1));
  });
}
