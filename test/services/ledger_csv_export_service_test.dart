import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/ledger_csv_export_service.dart';

/// WP-3 (D6) — التصدير ينتج ملفًا فعليًا: كل الحركات (قراءة مجزّأة)، ترميز
/// UTF-8 مع BOM، وعربية سليمة في Excel.
void main() {
  final base = DateTime.utc(2026, 10, 1, 12);

  Transaction tx(int index, {String? reference, String? customerId}) => Transaction(
        id: 'tx-$index',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: Money(minorUnits: 1000 + index, currencyCode: 'YER'),
        customerId: customerId,
        reference: reference,
        createdAt: base.subtract(Duration(hours: index)),
      );

  final _Clock clock = _Clock(base);

  test('ينتج BOM + سطر عناوين + سطر لكل حركة', () async {
    final pager = _Pager([tx(0), tx(1), tx(2)]);
    final service = LedgerCsvExportService(transactions: pager, clock: clock);

    final result = await service.build();
    expect(result, isA<Success<LedgerCsvExport>>());
    final export = (result as Success<LedgerCsvExport>).value;

    expect(export.hasBom, isTrue, reason: 'لا يوجد BOM — العربية ستتلف في Excel');
    expect(export.rowCount, 3);
    expect(export.fileName, endsWith('.csv'));
    expect(export.fileName, contains('الحركات'));

    final text = utf8.decode(export.bytes.sublist(3));
    final lines = text.trim().split('\n');
    expect(lines.length, 4, reason: 'عنوان + 3 حركات');
    expect(lines.first, LedgerCsvExportService.columns.join(','));
    expect(lines.first.contains('id'), isTrue);
  });

  test('يقرأ كل الصفحات بلا سقف 500', () async {
    final rows = List<Transaction>.generate(1200, (index) => tx(index));
    final pager = _Pager(rows);
    final service = LedgerCsvExportService(
      transactions: pager,
      clock: clock,
      pageSize: 100,
    );

    final result = await service.build();
    final export = (result as Success<LedgerCsvExport>).value;
    expect(export.rowCount, 1200);
    expect(pager.calls, 13, reason: '12 صفحة كاملة + صفحة فارغة تختم القراءة');
    expect(pager.lastOffset, 1200);
  });

  test('يهرّب الفواصل والعلامات المزدوجة في CSV', () async {
    final pager = _Pager([tx(0, reference: 'A,B', customerId: 'قول "مزدوج"')]);
    final service = LedgerCsvExportService(transactions: pager, clock: clock);

    final export =
        ((await service.build()) as Success<LedgerCsvExport>).value;
    final text = utf8.decode(export.bytes.sublist(3));
    expect(text.contains('"A,B"'), isTrue);
    expect(text.contains('"قول ""مزدوج"""'), isTrue);
  });

  test('مرشّح التاريخ يحترم from و to', () async {
    final pager = _Pager([tx(0), tx(1), tx(2), tx(3)]);
    final service = LedgerCsvExportService(transactions: pager, clock: clock);

    final from = base.subtract(const Duration(hours: 2));
    final to = base.subtract(const Duration(hours: 1));
    final export = ((await service.build(from: from, to: to))
        as Success<LedgerCsvExport>).value;
    expect(export.rowCount, 2);
  });

  test('فشل القراءة يُمرَّر كما هو بلا ملف جزئي', () async {
    final pager = _Pager(const <Transaction>[], failOnPage: 1);
    final service = LedgerCsvExportService(transactions: pager, clock: clock);
    final result = await service.build();
    expect(result, isA<Failure<LedgerCsvExport>>());
    expect((result as Failure<LedgerCsvExport>).error.code, 'page_failed');
  });

  test('قائمة فارغة تنتج ملفًا بعنوان فقط', () async {
    final pager = _Pager(const <Transaction>[]);
    final service = LedgerCsvExportService(transactions: pager, clock: clock);
    final export = ((await service.build()) as Success<LedgerCsvExport>).value;
    expect(export.rowCount, 0);
    final text = utf8.decode(export.bytes.sublist(3));
    expect(text.trim(), LedgerCsvExportService.columns.join(','));
  });

  test('اسم الملف يحمل التاريخ والوقت', () {
    expect(
      LedgerCsvExportService.fileNameAt(DateTime(2026, 10, 10, 20, 5)),
      'الحركات-2026-10-10_20-05.csv',
    );
  });
}

final class _Clock implements Clock {
  _Clock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

/// ناقل صفحات في الذاكرة: يخدم [limit]/[offset] بالترتيب نفسه.
final class _Pager implements TransactionPager {
  _Pager(this._rows, {this.failOnPage});

  final List<Transaction> _rows;
  final int? failOnPage;
  int calls = 0;
  int lastOffset = 0;

  @override
  Future<Result<List<Transaction>>> listPage({
    required int limit,
    required int offset,
  }) async {
    calls++;
    lastOffset = offset;
    if (failOnPage != null && calls == failOnPage) {
      return const Failure(AppFailure(code: 'page_failed', message: 'فشل'));
    }
    if (offset >= _rows.length) return const Success(<Transaction>[]);
    final end = (offset + limit).clamp(0, _rows.length);
    return Success(_rows.sublist(offset, end));
  }
}
