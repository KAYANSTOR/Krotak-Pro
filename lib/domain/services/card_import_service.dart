import 'dart:typed_data';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/card_import_log.dart';
import '../repositories/repositories.dart';
import 'card_import_file_reader.dart';
import 'card_import_parser.dart';
import 'card_import_preview.dart';
import 'services.dart';

/// WP-5 — مسار واحد لاستيراد الكروت من ملفات: قراءة → تحليل → معاينة → حفظ ذرّي → سجل.
///
/// القواعد المنفّذة (الخطة WP-5):
/// - **ذرّية:** الحفظ يمر بـ`CardCatalogService.importCards` داخل وحدة عمل
///   واحدة، فلا دفعة جزئية عند فشل التحقق.
/// - **بلا تكرار:** المقروض في المخزون (متوفر/محجوز/مباع) يُستبعد
///   قبل الحفظ، فلا يُنشأ كرت مكرر عند إعادة فتح العملية.
/// - **لا مساس مالي:** لا تُكتب أي حركة أو قيد محاسبي هنا.
final class CardImportService {
  const CardImportService({
    required this.cards,
    required this.catalog,
    required this.logs,
    required this.clock,
    required this.ids,
  });

  final CardRepository cards;
  final CardCatalogService catalog;
  final CardImportLogRepository logs;
  final Clock clock;
  final IdGenerator ids;

  /// تحليل النص/الملف: بلا كتابة أي صف في القاعدة.
  Future<Result<CardImportPreview>> analyze({
    required String raw,
    required CardImportFormat format,
    String? fileName,
  }) async {
    final parsed = CardImportParser.parse(raw, format: format);
    final existing = await cards.existingSerialsAmong(
      parsed.drafts.map((draft) => draft.serialNumber),
    );
    if (existing is Failure<Set<String>>) return Failure(existing.error);
    return Success(
      CardImportPreview(
        drafts: parsed.drafts,
        parseErrors: parsed.errors,
        stockDuplicateSerials: existing.value,
        fileName: fileName,
      ),
    );
  }

  /// قراءة ملف حقيقي وتحليله. يُسجّل الفشل بالعربية.
  Future<Result<CardImportReadOutcome>> readAndAnalyze({
    required String fileName,
    required List<int> bytes,
    required CardImportFormat format,
  }) async {
    final read = CardImportFileReader.read(
      fileName: fileName,
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    if (!read.isOk) {
      final reason = read.errorMessage ?? 'تعذر قراءة الملف';
      await recordFailure(
        fileName: fileName,
        fileKind: cardImportKindCode(fileName),
        reason: reason,
      );
      return Failure(
        AppFailure(
          code: read.errorCode ?? 'card_import_read_failed',
          message: reason,
        ),
      );
    }
    final analyzed = await analyze(raw: read.text, format: format, fileName: fileName);
    if (analyzed is Failure<CardImportPreview>) return Failure(analyzed.error);
    return Success(
      CardImportReadOutcome(
        preview: analyzed.value,
        fileKind: cardImportKindCode(fileName),
      ),
    );
  }

  /// تنفيذ الاستيراد ثم كتابة سجل العملية.
  Future<Result<CardImportOutcome>> commit({
    required CardImportPreview preview,
    required String fileKind,
    required String categoryId,
    String? categoryName,
  }) async {
    final startedAt = clock.now();
    final logId = ids.next('card-import');
    final total = preview.drafts.length + preview.parseErrors.length;
    final rejections = _rejections(preview);
    final base = CardImportLog(
      id: logId,
      fileName: preview.fileName ?? 'ملف مباشر',
      fileKind: fileKind,
      status: CardImportLogStatus.processing,
      totalRows: total,
      duplicateCount: preview.stockDuplicateCount,
      rejectedCount: preview.parseErrors.length,
      categoryId: categoryId,
      categoryName: categoryName,
      rejections: rejections,
      startedAt: startedAt,
    );
    // قيد «قيد المعالجة» قبل البدء: يبقى أثر للعملية حتى لو أُغلق التطبيق وسطها.
    await logs.save(base);

    if (!preview.canImport) {
      final reason = preview.parseErrors.isNotEmpty
          ? preview.parseErrors.first
          : 'كل أرقام الملف موجودة مسبقًا في المخزون';
      await logs.save(
        base.copyWith(
          status: CardImportLogStatus.failed,
          failureReason: reason,
          finishedAt: clock.now(),
        ),
      );
      return Failure(
        AppFailure(code: 'card_import_nothing_accepted', message: reason),
      );
    }

    final imported = await catalog.importCards(
      categoryId: categoryId,
      drafts: preview.acceptedDrafts,
    );
    if (imported is Failure<int>) {
      final reason = _arabicReason(imported.error);
      await logs.save(
        base.copyWith(
          status: CardImportLogStatus.failed,
          failureReason: reason,
          finishedAt: clock.now(),
        ),
      );
      return Failure(imported.error);
    }

    final accepted = imported.value;
    final log = base.copyWith(
      status: (preview.stockDuplicateCount > 0 || preview.parseErrors.isNotEmpty)
          ? CardImportLogStatus.completedWithNotes
          : CardImportLogStatus.completed,
      acceptedCount: accepted,
      finishedAt: clock.now(),
    );
    await logs.save(log);
    return Success(
      CardImportOutcome(
        acceptedCount: accepted,
        duplicateCount: preview.stockDuplicateCount,
        rejectedCount: preview.parseErrors.length,
        totalRows: total,
        log: log,
      ),
    );
  }

  /// تسجيل عملية فشلت قبل القراءة/التحليل (ملف مبدول أو فارغ أو تالف).
  Future<Result<void>> recordFailure({
    required String fileName,
    required String fileKind,
    required String reason,
    String? categoryId,
    String? categoryName,
  }) async {
    final now = clock.now();
    return logs.save(
      CardImportLog(
        id: ids.next('card-import'),
        fileName: fileName,
        fileKind: fileKind,
        status: CardImportLogStatus.failed,
        categoryId: categoryId,
        categoryName: categoryName,
        failureReason: reason,
        startedAt: now,
        finishedAt: now,
      ),
    );
  }

  List<CardImportRejection> _rejections(CardImportPreview preview) {
    final items = <CardImportRejection>[];
    for (final error in preview.parseErrors) {
      items.add(
        CardImportRejection(line: _lineOf(error), reason: error),
      );
    }
    for (final serial in preview.stockDuplicateSerials) {
      items.add(
        CardImportRejection(
          line: 0,
          reason: 'الرقم $serial موجود مسبقًا في المخزون',
        ),
      );
    }
    return items;
  }

  /// يستخرج رقم السطر من نص المحلّل («سطر 12: ...») و 0 إن لم يوجد.
  static int _lineOf(String message) {
    final match = RegExp(r'سطر\s+(\d+)').firstMatch(message);
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  /// رسالة عربية لسبب الفشل — بلا أي رمز برمجي في الواجهة.
  static String _arabicReason(AppFailure failure) {
    switch (failure.code) {
      case 'category_not_found':
        return 'الفئة غير موجودة — أعد اختيار الفئة';
      case 'category_inactive':
        return 'الفئة غير مفعّلة — فعّلها أو اختر فئة أخرى';
      case 'duplicate_serial':
        return 'رقم الكرت موجود مسبقًا — لم يُحفظ أي كرت جديد';
      case 'invalid_card_import':
        return failure.message;
      default:
        return 'تعذر إتمام الاستيراد — لم يُحفظ أي كرت';
    }
  }
}

/// ناتج قراءة ملف وتحليله (قبل الحفظ).
final class CardImportReadOutcome {
  const CardImportReadOutcome({required this.preview, required this.fileKind});
  final CardImportPreview preview;
  final String fileKind;
}

/// ناتج تنفيذ الاستيراد مع السجل المكتوب.
final class CardImportOutcome {
  const CardImportOutcome({
    required this.acceptedCount,
    required this.duplicateCount,
    required this.rejectedCount,
    required this.totalRows,
    required this.log,
  });

  final int acceptedCount;
  final int duplicateCount;
  final int rejectedCount;
  final int totalRows;
  final CardImportLog log;
}

/// رمز نوع الملف المخزّن في السجل.
String cardImportKindCode(String fileName) {
  final lower = fileName.trim().toLowerCase();
  if (lower.endsWith('.pdf')) return 'pdf';
  if (lower.endsWith('.xlsx')) return 'xlsx';
  if (lower.endsWith('.csv')) return 'csv';
  return 'file';
}
