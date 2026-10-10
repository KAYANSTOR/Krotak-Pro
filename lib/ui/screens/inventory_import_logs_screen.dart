import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card_import_log.dart';
import '../../domain/services/card_import_file_reader.dart';
import '../../domain/services/card_import_service.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../errors/user_facing_error_localizer.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_surface_card.dart';
import 'inventory_import_sheets.dart';

/// WP-5 (P1 — القرار D8) — «إدارة ملفات الاستيراد»:
/// قائمة عمليات الاستيراد من جدول `card_import_logs` (لا من قيم ثابتة)، مع
/// التفاصيل وإعادة المحاولة وتصدير التقرير وحذف السجل فقط.
class InventoryImportLogsScreen extends StatefulWidget {
  const InventoryImportLogsScreen({
    super.key,
    this.picker = pickCardImportFile,
    this.onImportRequested,
  });

  /// المنتقي المستخدم في «إعادة المحاولة» — قابل للحقن في الاختبارات.
  final CardImportFilePicker picker;

  /// يُستدعى من الحالة الفارغة لفتح ورقة الاستيراد.
  final Future<void> Function()? onImportRequested;

  @override
  State<InventoryImportLogsScreen> createState() =>
      _InventoryImportLogsScreenState();
}

class _InventoryImportLogsScreenState extends State<InventoryImportLogsScreen> {
  bool _loading = true;
  String? _error;
  List<CardImportLog> _logs = const <CardImportLog>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.cardImportLogs.listRecent(limit: 300);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Failure<List<CardImportLog>>) {
        _error = localizedError(result.error);
        _logs = const <CardImportLog>[];
      } else {
        _logs = (result as Success<List<CardImportLog>>).value;
      }
    });
  }

  Future<void> _retry(CardImportLog log) async {
    final categoryId = log.categoryId;
    if (categoryId == null || categoryId.isEmpty) {
      _notice('الفئة غير معروفة في هذا السجل — أعد الاستيراد من إدارة الكروت.');
      return;
    }
    final kind = _kindOf(log.fileKind);
    if (kind == CardImportFileKind.unsupported) {
      _notice('نوع الملف غير مدعوم في هذا السجل.');
      return;
    }
    setState(() => _busy = true);
    CardImportPickedFile? picked;
    try {
      picked = await widget.picker(kind);
    } catch (_) {
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
      format: CardImportFormat.serialAndPin,
    );
    if (!mounted) return;
    if (read is Failure<CardImportReadOutcome>) {
      setState(() => _busy = false);
      _notice(localizedError(read.error));
      await _load();
      return;
    }
    final readOk = read as Success<CardImportReadOutcome>;
    final committed = await c.cardImportService.commit(
      preview: readOk.value.preview,
      fileKind: readOk.value.fileKind,
      categoryId: categoryId,
      categoryName: log.categoryName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (committed is Failure<CardImportOutcome>) {
      _notice(localizedError(committed.error));
    } else {
      final ok = committed as Success<CardImportOutcome>;
      _notice('تم استيراد ${ok.value.acceptedCount} كرت.');
    }
    await _load();
  }

  Future<void> _exportReport(CardImportLog log) async {
    setState(() => _busy = true);
    final c = AppScope.of(context);
    final report = buildCardImportReport(log);
    final saved = await c.visibleStorage.saveToDownloads(
      bytes: report.bytes,
      fileName: report.fileName,
      mimeType: 'text/csv',
      subfolder: 'Exports',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved is Failure<String>) {
      _notice(localizedError(saved.error));
      return;
    }
    _notice(
      'تم تصدير تقرير النتائج إلى ${(saved as Success<String>).value}',
    );
  }

  Future<void> _deleteLog(CardImportLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'حذف سجل الاستيراد',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'يُحذف سجل العملية فقط. لا تُحذف أي كروت من المخزون ولا أي حركة مالية.

'
            'هل تريد المتابعة؟',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف السجل', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final c = AppScope.of(context);
    final deleted = await c.cardImportLogs.deleteLog(log.id);
    if (!mounted) return;
    if (deleted is Failure<void>) {
      _notice(localizedError(deleted.error));
      return;
    }
    _notice('تم حذف السجل فقط — الكروت لم تُمسّ.');
    await _load();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Tajawal')),
      ),
    );
  }

  static CardImportFileKind _kindOf(String code) {
    switch (code) {
      case 'pdf':
        return CardImportFileKind.pdf;
      case 'xlsx':
        return CardImportFileKind.xlsx;
      case 'csv':
        return CardImportFileKind.csv;
      default:
        return CardImportFileKind.unsupported;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          backgroundColor: palette.appBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary),
          ),
          title: const NetAppBarTitle(
            icon: Icons.folder_copy_rounded,
            title: 'إدارة ملفات الاستيراد',
            subtitle: 'سجل عمليات استيراد الكروت من الملفات',
          ),
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _logs.isEmpty
                    ? _emptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          NetSpacing.lg,
                          NetSpacing.sm,
                          NetSpacing.lg,
                          NetSpacing.xxl,
                        ),
                        itemCount: _logs.length,
                        itemBuilder: (ctx, index) => Padding(
                          padding: const EdgeInsets.only(bottom: NetSpacing.sm),
                          child: _logCard(context, _logs[index]),
                        ),
                      ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NetSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: KayanPalette.of(context).textSecondary,
            ),
            const SizedBox(height: NetSpacing.sm),
            const Text(
              'لا توجد عمليات استيراد بعد',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            const Text(
              'يُسجّل هنا كل ملف يُستورد منه الكروت: النوع والتاريخ والمقبول والمكرر والمرفوض.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12.5,
                color: KayanPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: NetSpacing.md),
            FilledButton.icon(
              onPressed: widget.onImportRequested == null
                  ? null
                  : () async {
                      await widget.onImportRequested!();
                      await _load();
                    },
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text(
                'استيراد ملف',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logCard(BuildContext context, CardImportLog log) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final color = switch (log.status) {
      CardImportLogStatus.completed => net.available,
      CardImportLogStatus.completedWithNotes => net.warning,
      CardImportLogStatus.failed => net.error,
      CardImportLogStatus.processing => net.pending,
    };
    return InkWell(
      onTap: () => _showDetails(log),
      borderRadius: NetRadii.mdAll,
      child: NetSurfaceCard(
        padding: const EdgeInsets.all(NetSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insert_drive_file_rounded, color: color),
                const SizedBox(width: NetSpacing.xs),
                Expanded(
                  child: Text(
                    log.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _chip(context, log.status.arabicLabel, color),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${log.fileKindLabel} · ${_formatDate(log.startedAt)}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11.5,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'المقروء ${log.readableRows} · المقبول ${log.acceptedCount} · المكرر ${log.duplicateCount} · المرفوض ${log.rejectedCount}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11.5,
                color: palette.textPrimary,
              ),
            ),
            if (log.failureReason != null && log.failureReason!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                log.failureReason!,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  color: net.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: NetRadii.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Future<void> _showDetails(CardImportLog log) async {
    await NetSheet.show<void>(
      context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: NetSheet(
          title: log.fileName,
          subtitle: '${log.fileKindLabel} · ${_formatDate(log.startedAt)}',
          icon: Icons.fact_check_rounded,
          children: [
            _detailRow(ctx, 'الحالة', log.status.arabicLabel),
            _detailRow(ctx, 'المقروء', '${log.readableRows}'),
            _detailRow(ctx, 'المقبول', '${log.acceptedCount}'),
            _detailRow(ctx, 'المكرر', '${log.duplicateCount}'),
            _detailRow(ctx, 'المرفوض', '${log.rejectedCount}'),
            if (log.categoryName != null)
              _detailRow(ctx, 'الفئة', log.categoryName!),
            if (log.failureReason != null)
              _detailRow(ctx, 'سبب الفشل', log.failureReason!),
            if (log.rejections.isNotEmpty) ...[
              const SizedBox(height: NetSpacing.sm),
              const Text(
                'الصفوف المرفوضة',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              for (final rejection in log.rejections.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    rejection.line > 0
                        ? 'سطر ${rejection.line}: ${rejection.reason}'
                        : rejection.reason,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11.5,
                      color: KayanPalette.of(ctx).textSecondary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: NetSpacing.md),
            FilledButton.icon(
              onPressed: _busy ? null : () => _retry(log),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _exportReport(log),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text(
                'تصدير تقرير النتائج',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _deleteLog(log),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text(
                'حذف السجل فقط',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تقرير نتائج عملية استيراد كجدول CSV بترميز UTF-8 مع BOM.
final class CardImportReportFile {
  const CardImportReportFile({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

CardImportReportFile buildCardImportReport(CardImportLog log) {
  final buffer = StringBuffer()
    ..writeln('id,fileName,fileKind,status,readable,accepted,duplicate,rejected,startedAt,failureReason');
  buffer.writeln(<String>[
    _csv(log.id),
    _csv(log.fileName),
    log.fileKind,
    log.status.code,
    '${log.readableRows}',
    '${log.acceptedCount}',
    '${log.duplicateCount}',
    '${log.rejectedCount}',
    log.startedAt.toIso8601String(),
    _csv(log.failureReason ?? ''),
  ].join(','));
  buffer.writeln('line,reason');
  for (final rejection in log.rejections) {
    buffer.writeln('${rejection.line},${_csv(rejection.reason)}');
  }
  final content = buffer.toString();
  final bytes = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
  return CardImportReportFile(
    bytes: bytes,
    fileName: 'تقرير-استيراد-${log.id}.csv',
  );
}

String _csv(String raw) {
  final value = raw.replaceAll('"', '""');
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"$value"';
  }
  return value;
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} · $hour:$minute';
}
