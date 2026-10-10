import 'dart:convert';
import 'dart:typed_data';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';

/// WP-3 (D6) — تصدير دفتر الحركات إلى ملف CSV فعلي.
///
/// - **كل** الحركات: قراءة مجزّأة عبر [TransactionPager] بدل سقف 500 صف.
/// - UTF-8 **مع BOM** حتى تظهر العربية سليمة في Excel.
/// - لا كتابة لأي ملف هنا: الخدمة تُنتج البايتات، والحفظ في مجلد عام عبر
///   `VisibleStorageService` (WP-S1) في الطبقة العلوية.
final class LedgerCsvExportService {
  const LedgerCsvExportService({
    required this.transactions,
    required this.clock,
    this.pageSize = 500,
  });

  final TransactionPager transactions;
  final Clock clock;
  final int pageSize;

  /// أعمدة الملف — ثابتة ومعلنة للاختبارات والواجهة.
  static const List<String> columns = <String>[
    'id',
    'type',
    'status',
    'minor',
    'currency',
    'customer',
    'reference',
    'createdAt',
  ];

  /// UTF-8 BOM — أول ثلاث بايتات في الملف.
  static const List<int> utf8Bom = <int>[0xEF, 0xBB, 0xBF];

  Future<Result<LedgerCsvExport>> build({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = <Transaction>[];
    var offset = 0;
    final size = pageSize <= 0 ? 500 : pageSize;
    while (true) {
      final page = await transactions.listPage(limit: size, offset: offset);
      if (page is Failure<List<Transaction>>) return Failure(page.error);
      final batch = (page as Success<List<Transaction>>).value;
      if (batch.isEmpty) break;
      for (final row in batch) {
        if (!_within(row, from, to)) continue;
        rows.add(row);
      }
      // الصفوف مرتّبة من الأحدث للأقدم: تجاوز `from` يعني أن ما بعده أقدم منه.
      if (from != null && batch.last.createdAt.isBefore(from)) break;
      if (batch.length < size) break;
      offset += size;
    }

    final buffer = StringBuffer()..writeln(columns.join(','));
    for (final row in rows) {
      buffer.writeln(<String>[
        _csv(row.id),
        row.type.name,
        row.status.name,
        '${row.amount.minorUnits}',
        row.amount.currencyCode,
        _csv(row.customerId ?? ''),
        _csv(row.reference ?? ''),
        row.createdAt.toIso8601String(),
      ].join(','));
    }

    final content = utf8.encode(buffer.toString());
    final bytes = Uint8List.fromList(<int>[...utf8Bom, ...content]);
    return Success(
      LedgerCsvExport(
        bytes: bytes,
        rowCount: rows.length,
        fileName: fileNameAt(clock.now()),
      ),
    );
  }

  static bool _within(Transaction row, DateTime? from, DateTime? to) {
    final at = row.createdAt;
    if (from != null && at.isBefore(from)) return false;
    if (to != null && at.isAfter(to)) return false;
    return true;
  }

  /// اسم ملف عربي مفهوم بالتاريخ والوقت (بلا رموز برمجية).
  static String fileNameAt(DateTime now) {
    final stamp = '${now.year}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '-${now.minute.toString().padLeft(2, '0')}';
    return 'الحركات-$stamp.csv';
  }

  static String _csv(String raw) {
    final value = raw.replaceAll('"', '""');
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"$value"';
    }
    return value;
  }
}

/// ناتج التصدير: البايتات الجاهزة للحفظ + عدد الصفوف + اسم الملف المقترح.
final class LedgerCsvExport {
  const LedgerCsvExport({
    required this.bytes,
    required this.rowCount,
    required this.fileName,
  });

  final Uint8List bytes;
  final int rowCount;
  final String fileName;

  bool get hasBom =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
}
