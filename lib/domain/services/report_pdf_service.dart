import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// صف عام لجدول تقرير PDF.
final class PdfTableRow {
  const PdfTableRow(this.cells);
  final List<String> cells;
}

/// بناء PDF عربي (RTL) بخط Tajawal المضمّن — بدون أرقام وهمية.
final class ReportPdfService {
  ReportPdfService._(this._regular, this._bold);

  final pw.Font _regular;
  final pw.Font _bold;

  static ReportPdfService? _instance;

  static Future<ReportPdfService> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final regularData = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
    final svc = ReportPdfService._(
      pw.Font.ttf(regularData),
      pw.Font.ttf(boldData),
    );
    _instance = svc;
    return svc;
  }

  /// تقرير مبيعات لفترة.
  Future<Uint8List> buildSalesReport({
    required String title,
    required String periodLabel,
    required String networkName,
    required DateTime generatedAt,
    required List<PdfTableRow> rows,
    required String totalLabel,
  }) {
    return _build(
      title: title,
      subtitle: periodLabel,
      networkName: networkName,
      generatedAt: generatedAt,
      headers: const ['التاريخ', 'العميل', 'المبلغ', 'المرجع'],
      rows: rows,
      footerNote: totalLabel,
    );
  }

  /// كشف / تقرير كروت مباعة.
  Future<Uint8List> buildSoldCardsReport({
    required String title,
    required String filterLabel,
    required String networkName,
    required DateTime generatedAt,
    required List<PdfTableRow> rows,
    required String totalLabel,
  }) {
    return _build(
      title: title,
      subtitle: filterLabel,
      networkName: networkName,
      generatedAt: generatedAt,
      headers: const ['السيريال', 'الفئة', 'العميل', 'الهاتف', 'تاريخ البيع', 'المبلغ'],
      rows: rows,
      footerNote: totalLabel,
    );
  }

  /// كشف حساب عميل / نقطة بيع.
  Future<Uint8List> buildLedgerStatement({
    required String title,
    required String accountLabel,
    required String networkName,
    required DateTime generatedAt,
    required String balanceLabel,
    required List<PdfTableRow> rows,
  }) {
    return _build(
      title: title,
      subtitle: accountLabel,
      networkName: networkName,
      generatedAt: generatedAt,
      headers: const ['التاريخ', 'النوع', 'البيان', 'المبلغ', 'الحالة'],
      rows: rows,
      footerNote: balanceLabel,
    );
  }

  /// ملخص تشغيلي من OpsSnapshot.
  Future<Uint8List> buildOpsSnapshot({
    required String networkName,
    required DateTime generatedAt,
    required List<PdfTableRow> metricRows,
  }) {
    return _build(
      title: 'الملخص التشغيلي',
      subtitle: 'أرقام حقيقية من الدفتر والمخزون',
      networkName: networkName,
      generatedAt: generatedAt,
      headers: const ['المؤشر', 'القيمة'],
      rows: metricRows,
      footerNote: null,
    );
  }

  Future<Uint8List> _build({
    required String title,
    required String subtitle,
    required String networkName,
    required DateTime generatedAt,
    required List<String> headers,
    required List<PdfTableRow> rows,
    required String? footerNote,
  }) async {
    final doc = pw.Document(
      title: title,
      author: networkName,
      creator: 'Krotak Pro',
    );

    final theme = pw.ThemeData.withFont(base: _regular, bold: _bold);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.all(28),
          textDirection: pw.TextDirection.rtl,
        ),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              networkName.isEmpty ? 'Krotak Pro' : networkName,
              style: pw.TextStyle(font: _bold, fontSize: 14),
              textAlign: pw.TextAlign.right,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              title,
              style: pw.TextStyle(font: _bold, fontSize: 18),
              textAlign: pw.TextAlign.right,
            ),
            pw.Text(
              subtitle,
              style: pw.TextStyle(font: _regular, fontSize: 11),
              textAlign: pw.TextAlign.right,
            ),
            pw.Text(
              'تاريخ الإصدار: ${_fmtDateTime(generatedAt)}',
              style: pw.TextStyle(font: _regular, fontSize: 9, color: PdfColors.grey700),
              textAlign: pw.TextAlign.right,
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Column(
          children: [
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'صفحة ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: pw.TextStyle(font: _regular, fontSize: 9, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Krotak Pro — تقرير محلي',
                  style: pw.TextStyle(font: _regular, fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[
            _table(headers, rows),
          ];
          if (footerNote != null && footerNote.trim().isNotEmpty) {
            widgets.add(pw.SizedBox(height: 12));
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  footerNote,
                  style: pw.TextStyle(font: _bold, fontSize: 12),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            );
          }
          return widgets;
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _table(List<String> headers, List<PdfTableRow> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows.map((r) => r.cells).toList(),
      headerStyle: pw.TextStyle(font: _bold, fontSize: 10),
      cellStyle: pw.TextStyle(font: _regular, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    );
  }

  static String _fmtDateTime(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
