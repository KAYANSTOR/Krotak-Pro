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
