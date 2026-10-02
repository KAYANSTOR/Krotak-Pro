import '../entities/transaction.dart';
import 'report_pdf_service.dart';

/// صف حركة لكشف نقطة البيع قبل تحويله إلى جدول PDF.
final class PosStatementPdfLine {
  const PosStatementPdfLine({
    required this.occurredAt,
    required this.kind,
    required this.description,
    required this.amountMinor,
    required this.status,
  });

  final DateTime occurredAt;
  final String kind;
  final String description;
  final int amountMinor;
  final String status;
}

/// اسم النوع العربي كما يظهر في كشف نقطة البيع.
String posStatementKindLabel(TransactionType type) {
  return switch (type) {
    TransactionType.deposit => 'إيداع',
    TransactionType.withdrawal => 'سحب',
    TransactionType.sale => 'بيع',
    TransactionType.settlement => 'تسوية',
    TransactionType.reversal => 'عكس',
    TransactionType.advance => 'سلفة',
    TransactionType.reward => 'مكافأة',
  };
}

/// اسم الحالة العربي. لا يُكتب اسم التعداد الإنجليزي في الملف.
String posStatementStatusLabel(TransactionStatus status) {
  return switch (status) {
    TransactionStatus.pending => 'معلّقة',
    TransactionStatus.completed => 'مكتملة',
    TransactionStatus.reversed => 'معكوسة',
    TransactionStatus.rejected => 'مرفوضة',
  };
}

/// كل حركات دفتر العميل المرتبط بالنقطة منذ الإنشاء، الأقدم أولاً.
/// لا يقرأ قاعدة البيانات ولا يستبعد التسويات المعروضة في الورقة.
List<PosStatementPdfLine> posStatementLinesFromLedger(
  Iterable<Transaction> transactions,
) {
  final lines = [
    for (final txn in transactions)
      PosStatementPdfLine(
        occurredAt: txn.createdAt,
        kind: posStatementKindLabel(txn.type),
        description: txn.reference?.trim().isNotEmpty == true
            ? txn.reference!.trim()
            : posStatementKindLabel(txn.type),
        amountMinor: txn.amount.minorUnits,
        status: posStatementStatusLabel(txn.status),
      ),
  ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  return lines;
}

/// يبني صفوف كشف نقطة بيع واحدة: الرصيد والسقف ثم الحركات.
/// لا يقرأ قاعدة البيانات ولا يغيّر الدفتر.
List<PdfTableRow> buildPosStatementPdfRows({
  required int balanceMinor,
  required int? creditLimitMinor,
  required String phone,
  required List<PosStatementPdfLine> lines,
}) {
  String money(int minor) => (minor / 100).toStringAsFixed(2);
  String when(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  final balanceKind = balanceMinor < 0 ? 'مديونية' : 'رصيد دائن';
  return [
    PdfTableRow([
      '—',
      'جوال',
      phone.trim().isEmpty ? '—' : phone.trim(),
      '—',
      'مرجع',
    ]),
    PdfTableRow([
      '—',
      balanceKind,
      'الرصيد الحالي لنقطة البيع',
      money(balanceMinor.abs()),
      'حالي',
    ]),
    PdfTableRow([
      '—',
      'سقف الدين',
      creditLimitMinor == null ? 'غير محدد' : 'سقف الدين المعتمد',
      creditLimitMinor == null ? '—' : money(creditLimitMinor),
      creditLimitMinor == null ? 'غير مفعّل' : 'مفعّل',
    ]),
    for (final line in lines)
      PdfTableRow([
        when(line.occurredAt),
        line.kind,
        line.description,
        money(line.amountMinor.abs()),
        line.status,
      ]),
  ];
}
