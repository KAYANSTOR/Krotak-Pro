/// WP-S4 / WP-5 — سجل عملية استيراد كروت من ملف (القرار D8).
///
/// الجدول المدعوم `card_import_logs` في القاعدة، وهذه الكيانات
/// هي واجهة القراءة/الكتابة الوحيدة لها في الطبقات العليا.
library;

/// حالة عملية الاستيراد — مصدر الحقيقة للعرض والإجراءات المتاحة.
enum CardImportLogStatus {
  processing('processing', 'قيد المعالجة'),
  completed('completed', 'مكتمل'),
  completedWithNotes('completed_with_notes', 'مكتمل مع ملاحظات'),
  failed('failed', 'فشل');

  const CardImportLogStatus(this.code, this.arabicLabel);

  /// الرمز المخزّن في قاعدة البيانات — لا يُعرض للمستخدم أبدًا.
  final String code;

  /// الاسم العربي الوحيد المعروض في الواجهة.
  final String arabicLabel;

  bool get isFinished => this != CardImportLogStatus.processing;

  static CardImportLogStatus fromCode(String? code) {
    for (final value in CardImportLogStatus.values) {
      if (value.code == code) return value;
    }
    return CardImportLogStatus.processing;
  }
}

/// سبب رفض صف واحد من الملف — بالعربية دائمًا.
final class CardImportRejection {
  const CardImportRejection({required this.line, required this.reason});

  /// رقم السطر في الملف (1-based)، و 0 لسبب عام بلا سطر.
  final int line;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{'line': line, 'reason': reason};

  static CardImportRejection fromJson(Map<String, Object?> json) {
    final raw = json['line'];
    final line = raw is int ? raw : int.tryParse('${raw ?? 0}') ?? 0;
    return CardImportRejection(
      line: line,
      reason: '${json['reason'] ?? ''}',
    );
  }
}

/// سجل عملية استيراد واحدة.
final class CardImportLog {
  const CardImportLog({
    required this.id,
    required this.fileName,
    required this.fileKind,
    required this.status,
    required this.startedAt,
    this.totalRows = 0,
    this.acceptedCount = 0,
    this.duplicateCount = 0,
    this.rejectedCount = 0,
    this.categoryId,
    this.categoryName,
    this.failureReason,
    this.rejections = const <CardImportRejection>[],
    this.finishedAt,
  });

  final String id;
  final String fileName;

  /// امتداد الملف المطبّع: pdf | xlsx | csv.
  final String fileKind;
  final CardImportLogStatus status;

  /// عدد الصفوف المقروءة من الملف.
  final int totalRows;
  final int acceptedCount;
  final int duplicateCount;
  final int rejectedCount;
  final String? categoryId;
  final String? categoryName;

  /// سبب الفشل العام بالعربية (مثل: تعذر قراءة الملف).
  final String? failureReason;
  final List<CardImportRejection> rejections;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// الاسم العربي لنوع الملف — أعلام ملفات مسموحة.
  String get fileKindLabel {
    switch (fileKind) {
      case 'pdf':
        return 'PDF';
      case 'xlsx':
        return 'Excel';
      case 'csv':
        return 'CSV';
      default:
        return 'ملف';
    }
  }

  bool get hasNotes => rejectedCount > 0 || duplicateCount > 0;

  int get readableRows => acceptedCount + duplicateCount + rejectedCount;

  CardImportLog copyWith({
    CardImportLogStatus? status,
    int? totalRows,
    int? acceptedCount,
    int? duplicateCount,
    int? rejectedCount,
    String? categoryId,
    String? categoryName,
    String? failureReason,
    List<CardImportRejection>? rejections,
    DateTime? finishedAt,
  }) {
    return CardImportLog(
      id: id,
      fileName: fileName,
      fileKind: fileKind,
      status: status ?? this.status,
      totalRows: totalRows ?? this.totalRows,
      acceptedCount: acceptedCount ?? this.acceptedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      failureReason: failureReason ?? this.failureReason,
      rejections: rejections ?? this.rejections,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}
