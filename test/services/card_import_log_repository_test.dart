import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card_import_log.dart';

/// WP-S4 — دورة كاملة على مستودع سجل عمليات استيراد الكروت:
/// الحفظ والقراءة والترتيب والعد والحذف (السجل فقط).
void main() {
  late AppDatabase database;
  late LocalCardImportLogRepository logs;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    logs = LocalCardImportLogRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  CardImportLog buildLog({
    required String id,
    String fileName = 'كروت-المورد.csv',
    String fileKind = 'csv',
    CardImportLogStatus status = CardImportLogStatus.completed,
    int totalRows = 10,
    int acceptedCount = 8,
    int duplicateCount = 1,
    int rejectedCount = 1,
    DateTime? startedAt,
    List<CardImportRejection> rejections = const <CardImportRejection>[],
    String? failureReason,
  }) {
    final started = startedAt ?? DateTime(2026, 10, 10, 9, 30);
    return CardImportLog(
      id: id,
      fileName: fileName,
      fileKind: fileKind,
      status: status,
      totalRows: totalRows,
      acceptedCount: acceptedCount,
      duplicateCount: duplicateCount,
      rejectedCount: rejectedCount,
      categoryId: 'cat-1',
      categoryName: 'فئة التجربة',
      failureReason: failureReason,
      rejections: rejections,
      startedAt: started,
      finishedAt: started.add(const Duration(seconds: 4)),
    );
  }

  test('تحفظ السجل وتقرأه بكل حقوله بما فيها العربية', () async {
    final saved = await logs.save(buildLog(
      id: 'log-1',
      status: CardImportLogStatus.completedWithNotes,
      rejections: const <CardImportRejection>[
        CardImportRejection(line: 3, reason: 'سطر 3: يُتوقّع رقم كرت ورمز سري'),
        CardImportRejection(line: 7, reason: 'سطر 7: تكرار رقم الكرت 776733907'),
      ],
    ));
    expect(saved, isA<Success<void>>());

    final found = await logs.findById('log-1');
    final log = (found as Success<CardImportLog?>).value!;
    expect(log.fileName, 'كروت-المورد.csv');
    expect(log.fileKind, 'csv');
    expect(log.fileKindLabel, 'CSV');
    expect(log.status, CardImportLogStatus.completedWithNotes);
    expect(log.status.arabicLabel, 'مكتمل مع ملاحظات');
    expect(log.totalRows, 10);
    expect(log.acceptedCount, 8);
    expect(log.duplicateCount, 1);
    expect(log.rejectedCount, 1);
    expect(log.categoryName, 'فئة التجربة');
    expect(log.rejections, hasLength(2));
    expect(log.rejections.first.line, 3);
    expect(log.rejections.first.reason, contains('رقم كرت'));
    expect(log.startedAt.toUtc(), DateTime.utc(2026, 10, 10, 9, 30));
    expect(log.finishedAt, isNotNull);
  });

  test('الحفظ بالمعرّف نفسه يُحدّث ولا يُكرّر', () async {
    await logs.save(buildLog(id: 'log-1', status: CardImportLogStatus.processing, acceptedCount: 0));
    final first = (await logs.findById('log-1') as Success<CardImportLog?>).value!;
    expect(first.status, CardImportLogStatus.processing);

    await logs.save(buildLog(id: 'log-1', acceptedCount: 8));
    expect((await logs.count() as Success<int>).value, 1);
    final updated = (await logs.findById('log-1') as Success<CardImportLog?>).value!;
    expect(updated.status, CardImportLogStatus.completed);
    expect(updated.acceptedCount, 8);
  });

  test('القائمة من الأحدث للأقدم والعد مطابق', () async {
    await logs.save(buildLog(id: 'old', startedAt: DateTime(2026, 10, 1, 8)));
    await logs.save(buildLog(id: 'new', startedAt: DateTime(2026, 10, 10, 8)));
    final listed = await logs.listRecent();
    final rows = (listed as Success<List<CardImportLog>>).value;
    expect(rows.map((row) => row.id).toList(), <String>['new', 'old']);
    expect((await logs.count() as Success<int>).value, 2);
  });

  test('حذف السجل لا يمس الكروت ولا الحركات المالية', () async {
    await database.into(database.cards).insert(
          CardsCompanion.insert(
            id: 'card-1',
            categoryId: 'cat-1',
            serialNumber: 'S-1',
            secretCode: 'P-1',
            status: 'available',
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            type: 'deposit',
            status: 'completed',
            amountMinorUnits: 500,
            currencyCode: 'YER',
            createdAt: DateTime(2026, 10, 10, 8),
          ),
        );
    await logs.save(buildLog(id: 'log-1'));

    final deleted = await logs.deleteLog('log-1');
    expect(deleted, isA<Success<void>>());
    expect((await logs.findById('log-1') as Success<CardImportLog?>).value, isNull);
    expect(await database.select(database.cards).get(), hasLength(1));
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test('السجل الفاشل يحفظ السبب العربي بلا نص لاتيني في العرض', () async {
    await logs.save(buildLog(
      id: 'failed-1',
      fileKind: 'xlsx',
      status: CardImportLogStatus.failed,
      acceptedCount: 0,
      duplicateCount: 0,
      rejectedCount: 0,
      failureReason: 'تعذر قراءة ورقة Excel',
    ));
    final log = (await logs.findById('failed-1') as Success<CardImportLog?>).value!;
    expect(log.status, CardImportLogStatus.failed);
    expect(log.fileKindLabel, 'Excel');
    expect(log.failureReason, 'تعذر قراءة ورقة Excel');
  });
}
