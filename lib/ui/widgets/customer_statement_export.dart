import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../theme/kayan_palette.dart';

/// يبني نص كشف الحساب الظاهر في الواجهة — بلا استعلام جديد.
String buildCustomerStatementText({
  required Customer customer,
  required List<CustomerIdentifier> identifiers,
  required Money? balance,
  required List<Transaction> recent,
  required String Function(Money?) formatMoney,
  required String Function(DateTime) formatTime,
}) {
  final phones = identifiers
      .where((e) => e.type == CustomerIdentifierType.phoneNumber)
      .map((e) => e.value)
      .toList();
  final lines = <String>[
    'NET — كشف حساب',
    'الاسم: ${customer.displayName}',
    if (phones.isNotEmpty) 'الجوال: ${phones.join(' · ')}',
    'الرصيد: ${formatMoney(balance)}',
    'عدد العمليات الظاهرة: ${recent.length}',
    if (recent.isNotEmpty) '---',
    ...recent.map((tx) {
      final credit = tx.type == TransactionType.deposit ||
          tx.type == TransactionType.reward;
      final sign = credit ? '+' : '-';
      return '$sign${formatMoney(tx.amount)}  ${formatTime(tx.createdAt)}  ${tx.reference ?? ''}';
    }),
  ];
  return lines.join('\n');
}

/// ورقة تصدير: نسخ نص، حفظ نص، حفظ صورة PNG من معاينة Tajawal.
Future<void> showCustomerStatementExportSheet({
  required BuildContext context,
  required String statementText,
  required Widget preview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _StatementExportSheet(
      statementText: statementText,
      preview: preview,
    ),
  );
}

class _StatementExportSheet extends StatefulWidget {
  const _StatementExportSheet({
    required this.statementText,
    required this.preview,
  });

  final String statementText;
  final Widget preview;

  @override
  State<_StatementExportSheet> createState() => _StatementExportSheetState();
}

class _StatementExportSheetState extends State<_StatementExportSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.statementText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم نسخ كشف الحساب — يمكنك لصقه للمشاركة',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
  }

  Future<void> _saveText() async {
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name =
          'net-statement-${DateTime.now().millisecondsSinceEpoch}.txt';
      await File(p.join(dir.path, name)).writeAsString(widget.statementText);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ النسخة النصية: $name',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر حفظ الملف النصي',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveImage() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('no-boundary');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('no-bytes');
      final dir = await getApplicationDocumentsDirectory();
      final name =
          'net-statement-${DateTime.now().millisecondsSinceEpoch}.png';
      await File(p.join(dir.path, name)).writeAsBytes(
        bytes.buffer.asUint8List(),
        flush: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ صورة الكشف: $name',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر حفظ صورة الكشف',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تصدير كشف الحساب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: widget.preview,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _copy,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('نسخ', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _saveText,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('حفظ نص', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _saveImage,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('حفظ صورة', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
