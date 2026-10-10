import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/services/card_import_file_reader.dart';
import '../../domain/services/card_import_preview.dart';
import '../../domain/services/card_import_service.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../errors/user_facing_error_localizer.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_surface_card.dart';

/// WP-5 — ورقة «استيراد كروت من ملف»: ثلاثة صفوف
/// (PDF / Excel / CSV)، كل صف يفتح منتقي الملفات بامتداده فقط، ثم
/// يمر الملف بالقارئ ← المحلّل ← المعاينة ← الحفظ الذرّي.
///
/// المنتقي محقون ([picker]) ليُختبر كل صف بمنتقي محاكى.
final class CardImportPickedFile {
  const CardImportPickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// دالة فتح المنتقي لنوع ملف واحد.
typedef CardImportFilePicker = Future<CardImportPickedFile?> Function(
  CardImportFileKind kind,
);

/// الصفوف المعروضة في الورقة — بالترتيب.
const List<CardImportFileKind> cardImportSheetKinds = <CardImportFileKind>[
  CardImportFileKind.pdf,
  CardImportFileKind.xlsx,
  CardImportFileKind.csv,
];

/// المنتقي الحقيقي: يقبل امتدادًا واحدًا لكل صف.
Future<CardImportPickedFile?> pickCardImportFile(CardImportFileKind kind) async {
  final extension = cardImportKindExtension(kind);
  if (extension.isEmpty) return null;
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: <String>[extension],
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  var bytes = file.bytes;
  if ((bytes == null || bytes.isEmpty) && (file.path?.isNotEmpty ?? false)) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null || bytes.isEmpty) return null;
  return CardImportPickedFile(name: file.name, bytes: bytes);
}

/// امتداد الملف المسموح لكل نوع.
String cardImportKindExtension(CardImportFileKind kind) {
  switch (kind) {
    case CardImportFileKind.pdf:
      return 'pdf';
    case CardImportFileKind.xlsx:
      return 'xlsx';
    case CardImportFileKind.csv:
      return 'csv';
    case CardImportFileKind.unsupported:
      return '';
  }
}

/// عنوان الصف العربي.
String cardImportKindTitle(CardImportFileKind kind) {
  switch (kind) {
    case CardImportFileKind.pdf:
      return 'استيراد ملف PDF';
    case CardImportFileKind.xlsx:
      return 'استيراد ملف Excel';
    case CardImportFileKind.csv:
      return 'استيراد ملف CSV';
    case CardImportFileKind.unsupported:
      return 'ملف غير مدعوم';
  }
}

/// وصف الصف بالعربية.
String cardImportKindDescription(CardImportFileKind kind) {
  switch (kind) {
    case CardImportFileKind.pdf:
      return 'استخراج الكروت من ملفات الموردين';
    case CardImportFileKind.xlsx:
      return 'ورقة Excel بعمودي الرقم والرمز السري';
    case CardImportFileKind.csv:
      return 'ملف نصي مفصول بفاصلة أو فاصلة منقوطة';
    case CardImportFileKind.unsupported:
      return 'امتداد غير مدعوم';
  }
}

/// يفتح ورقة استيراد الكروت من ملف.
Future<void> showCardImportFileSheet(
  BuildContext context, {
  required String categoryId,
  required String categoryName,
  required List<CardCategory> categories,
  required Future<void> Function() onDone,
  CardImportFilePicker picker = pickCardImportFile,
  CardImportFormat format = CardImportFormat.serialAndPin,
}) {
  return NetSheet.show<void>(
    context,
    builder: (ctx) => _CardImportFileSheet(
      categoryId: categoryId,
      categoryName: categoryName,
      categories: categories,
      onDone: onDone,
      picker: picker,
      format: format,
    ),
  );
}

class _CardImportFileSheet extends StatefulWidget {
  const _CardImportFileSheet({
    required this.categoryId,
    required this.categoryName,
    required this.categories,
    required this.onDone,
    required this.picker,
    required this.format,
  });

  final String categoryId;
  final String categoryName;
  final List<CardCategory> categories;
  final Future<void> Function() onDone;
  final CardImportFilePicker picker;
  final CardImportFormat format;

  @override
  State<_CardImportFileSheet> createState() => _CardImportFileSheetState();
}

class _CardImportFileSheetState extends State<_CardImportFileSheet> {
  bool _busy = false;
  String? _error;
  CardImportPreview? _preview;
  String _fileKind = 'file';
  late String _categoryId;
  late String _categoryName;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _categoryName = widget.categoryName;
  }

  Future<void> _pick(CardImportFileKind kind) async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    CardImportPickedFile? picked;
    try {
      picked = await widget.picker(kind);
    } catch (error) {
      picked = null;
    }
    if (!mounted) return;
    if (picked == null) {
      setState(() => _busy = false);
      return;
    }
    final c = AppScope.of(context);
    final read = await c.cardImportService.readAndAnalyze(
      fileName: picked.name,
      bytes: picked.bytes,
      format: widget.format,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (read is Failure<CardImportReadOutcome>) {
        _error = localizedError(read.error);
        _preview = null;
      } else {
        final ok = read as Success<CardImportReadOutcome>;
        _preview = ok.value.preview;
        _fileKind = ok.value.fileKind;
      }
    });
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null || !preview.canImport) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.cardImportService.commit(
      preview: preview,
      fileKind: _fileKind,
      categoryId: _categoryId,
      categoryName: _categoryName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is Failure<CardImportOutcome>) {
      setState(() => _error = localizedError(result.error));
      return;
    }
    final outcome = (result as Success<CardImportOutcome>).value;
    final notes = <String>[
      if (outcome.duplicateCount > 0) 'تم تخطي ${outcome.duplicateCount} مكرر',
      if (outcome.rejectedCount > 0) '${outcome.rejectedCount} سطر مرفوض',
    ];
    final suffix = notes.isEmpty ? '' : ' — ${notes.join(' · ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم استيراد ${outcome.acceptedCount} كرت$suffix',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    await widget.onDone();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final preview = _preview;
    return NetSheet(
      title: 'استيراد كروت من ملف',
      subtitle: 'اختر ملف الاستيراد لتغذية مخزون الكروت تلقائياً',
      icon: Icons.upload_file_rounded,
      children: [
        DropdownButtonFormField<String>(
          value: _categoryId,
          decoration: const InputDecoration(
            labelText: 'الفئة',
            border: OutlineInputBorder(),
          ),
          items: widget.categories
              .map(
                (category) => DropdownMenuItem<String>(
                  value: category.id,
                  child: Text(
                    category.name,
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _categoryId = value;
                    for (final category in widget.categories) {
                      if (category.id == value) _categoryName = category.name;
                    }
                  });
                },
        ),
        const SizedBox(height: NetSpacing.sm),
        for (final kind in cardImportSheetKinds) ...[
          _ImportRow(
            title: cardImportKindTitle(kind),
            description: cardImportKindDescription(kind),
            extension: cardImportKindExtension(kind),
            icon: _iconFor(kind),
            enabled: !_busy,
            onTap: () => _pick(kind),
          ),
          const SizedBox(height: NetSpacing.xs),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: NetSpacing.sm),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NetSpacing.xs),
            child: Text(
              _error!,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12.5,
                color: palette.textPrimary,
              ),
            ),
          ),
        if (preview != null) ...[
          const SizedBox(height: NetSpacing.sm),
          _ImportPreview(
            preview: preview,
            onImport: _busy ? null : _commit,
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(CardImportFileKind kind) {
    switch (kind) {
      case CardImportFileKind.pdf:
        return Icons.picture_as_pdf_rounded;
      case CardImportFileKind.xlsx:
        return Icons.table_chart_rounded;
      case CardImportFileKind.csv:
        return Icons.description_rounded;
      case CardImportFileKind.unsupported:
        return Icons.insert_drive_file_rounded;
    }
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({
    required this.title,
    required this.description,
    required this.extension,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final String extension;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: NetRadii.mdAll,
      child: NetSurfaceCard(
        padding: const EdgeInsets.all(NetSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: palette.primary),
            const SizedBox(width: NetSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NetSpacing.xs),
            Icon(Icons.chevron_left_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.preview, required this.onImport});

  final CardImportPreview preview;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final reasons = <String>[
      ...preview.parseErrors.take(5),
      for (final serial in preview.stockDuplicateSerials.take(5))
        'الرقم $serial موجود مسبقًا في المخزون',
    ];
    return NetSurfaceCard(
      padding: const EdgeInsets.all(NetSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'نتيجة المعاينة',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: NetSpacing.xs),
          _countRow(context, 'المقروء', preview.drafts.length + preview.parseErrors.length),
          _countRow(context, 'المقبول', preview.acceptedCount),
          _countRow(context, 'مكرر في المخزون', preview.stockDuplicateCount),
          _countRow(context, 'مرفوض', preview.parseErrors.length),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: NetSpacing.xs),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $reason',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: NetSpacing.sm),
          FilledButton.icon(
            onPressed: preview.canImport ? onImport : null,
            icon: const Icon(Icons.download_done_rounded, size: 18),
            label: const Text(
              'استيراد',
              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
            ),
          ),
          if (!preview.canImport)
            Padding(
              padding: const EdgeInsets.only(top: NetSpacing.xs),
              child: Text(
                'لا توجد أسطر صالحة للاستيراد في هذا الملف',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _countRow(BuildContext context, String label, int value) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12.5,
                color: palette.textSecondary,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
