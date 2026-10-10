import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/ledger_csv_export_service.dart';
import '../../../domain/services/local_maintenance_service.dart';
import '../../../domain/services/local_message_recovery_service.dart';
import '../../app_scope.dart';
import '../../errors/user_facing_error_localizer.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/net/net_surface_card.dart';

/// WP-3 — شاشة صيانة واحدة تجمع: تنظيف السجلات، التنظيف العميق، تصدير السجل.
///
/// القواعد المنفّذة:
/// - **عملية واحدة نشطة** في كل مرة؛ بقية الأزرار معطّلة بوضوح.
/// - كل نتيجة تُعرض بالعربية عبر `localizedError` — بلا `e.toString()`.
/// - التنظيف العميق يذكر ما يُنفَّذ فعلًا
///   ([LocalMaintenanceService.deepCleanSummaryAr]).
/// - التصدير ينتج **ملف CSV فعلي** في `Download/Krotak Pro/Exports/` (D6)
///   ويُشارَك كملف، و`lastExportAt` يُكتب **عند نجاح التصدير فقط**.
class MaintenanceHubScreen extends StatefulWidget {
  const MaintenanceHubScreen({super.key});

  @override
  State<MaintenanceHubScreen> createState() => _MaintenanceHubScreenState();
}

class _MaintenanceHubScreenState extends State<MaintenanceHubScreen> {
  bool _loading = true;
  int _pending = 0;
  int _rejected = 0;
  int _failed = 0;
  DatabaseSizeReport? _size;
  String? _status;
  String? _error;

  /// قفل التزامن: اسم العملية النشطة أو null.
  String? _running;

  String? _exportPath;
  int? _exportRows;

  bool get _busy => _running != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final pending = await c.messages.pendingProcessing();
    final rejected =
        await c.messages.listByStatus(MessageProcessingStatus.rejected);
    final failed =
        await c.messages.listByStatus(MessageProcessingStatus.failed);
    final size = await c.maintenanceService.inspectDatabase();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _size = size is Success<DatabaseSizeReport> ? size.value : null;
      if (pending is Failure<List<IncomingMessage>>) {
        _error = localizedError(pending.error);
        return;
      }
      if (rejected is Failure<List<IncomingMessage>>) {
        _error = localizedError(rejected.error);
        return;
      }
      if (failed is Failure<List<IncomingMessage>>) {
        _error = localizedError(failed.error);
        return;
      }
      _error = null;
      _pending = (pending as Success<List<IncomingMessage>>).value.length;
      _rejected = (rejected as Success<List<IncomingMessage>>).value.length;
      _failed = (failed as Success<List<IncomingMessage>>).value.length;
    });
  }

  Future<void> _run(String name, Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _running = name;
      _status = null;
    });
    String message;
    try {
      message = await action();
    } catch (error) {
      message = localizedError(error);
    }
    if (!mounted) return;
    setState(() {
      _running = null;
      _status = message;
    });
    await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String accept,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title, style: _titleStyle(context)),
          content: Text(body, style: _bodyStyle(context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(accept, style: const TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<String> _recoverPending() async {
    final c = AppScope.of(context);
    final result = await c.recoveryService.recoverPending();
    if (result is Failure<MessageRecoveryReport>) {
      return localizedError(result.error);
    }
    final report = (result as Success<MessageRecoveryReport>).value;
    if (report.attempted == 0) return 'لا توجد رسائل معلّقة بحاجة إلى استعادة.';
    return 'تمت استعادة الرسائل المعلّقة: '
        'حُوّلت للمعالجة ${report.processed}، '
        'تُخطّيت ${report.skipped}، '
        'فشلت ${report.failed}.';
  }

  Future<String> _purge() async {
    final confirmed = await _confirm(
      title: 'تأكيد تنظيف السجلات',
      body: 'سيُحذف فقط: الرسائل المرفوضة الأقدم من 30 يوماً، والمكتملة الأقدم '
          'من 3 أيام، والمستنفدة الأقدم من 30 يوماً.\n'
          'لن تُمس المبيعات ولا القيود المحاسبية ولا الكروت ولا العملاء.\n\n'
          'هل تريد المتابعة؟',
      accept: 'تنظيف',
    );
    if (!confirmed) return 'لم يُنفّذ أي حذف.';
    final c = AppScope.of(context);
    final result = await c.maintenanceService.purgeExpiredMessages();
    if (result is Failure<MaintenanceReport>) {
      return localizedError(result.error);
    }
    final report = (result as Success<MaintenanceReport>).value;
    final failures =
        report.errors.isEmpty ? '' : ' (تعذر حذف ${report.errors.length} رسالة)';
    return 'حُذفت ${report.deletedRejected} رسالة مرفوضة، '
        'و${report.deletedProcessed} مكتملة، '
        'و${report.deletedFailedMax} مستنفدة$failures.';
  }

  Future<String> _deepClean() async {
    final before = _size?.logicalBytes;
    final confirmed = await _confirm(
      title: 'تأكيد التنظيف العميق',
      body: '${LocalMaintenanceService.deepCleanSummaryAr}\n\n'
          'قد يستغرق بعض الوقت. هل تريد المتابعة؟',
      accept: 'تنظيف عميق',
    );
    if (!confirmed) return 'لم يُنفّذ أي تنظيف عميق.';
    final c = AppScope.of(context);
    final result = await c.maintenanceService.runDeepClean();
    if (result is Failure<DeepCleanReport>) {
      return localizedError(result.error);
    }
    final report = (result as Success<DeepCleanReport>).value;
    final after = report.sizeAfterBytes ?? before;
    final head = 'اكتمل التنظيف العميق في ${report.durationMs} مللي ثانية.';
    if (before == null || after == null) return head;
    final freed = before - after;
    final sizeLine =
        'حجم قاعدة البيانات: ${formatBytes(before)} ← ${formatBytes(after)}';
    if (freed > 0) return '$head $sizeLine (حُرّر ${formatBytes(freed)}).';
    return '$head $sizeLine (لا مساحة قابلة للتحرير حالياً).';
  }

  Future<String> _export() async {
    final c = AppScope.of(context);
    final built = await c.ledgerCsvExport.build();
    if (built is Failure<LedgerCsvExport>) {
      return localizedError(built.error);
    }
    final export = (built as Success<LedgerCsvExport>).value;
    final saved = await c.visibleStorage.saveToDownloads(
      bytes: export.bytes,
      fileName: export.fileName,
      mimeType: 'text/csv',
      subfolder: 'Exports',
    );
    if (saved is Failure<String>) {
      return localizedError(saved.error);
    }
    final path = (saved as Success<String>).value;
    await c.settings.save(
      AppSetting(
        key: SettingKeys.lastExportAt,
        value: c.clock.now().toIso8601String(),
        updatedAt: c.clock.now(),
      ),
    );
    if (mounted) {
      setState(() {
        _exportPath = path;
        _exportRows = export.rowCount;
      });
    }
    return 'تم تصدير ${export.rowCount} حركة إلى ملف CSV في مجلد التنزيلات.';
  }

  Future<void> _shareExport() async {
    final c = AppScope.of(context);
    final built = await c.ledgerCsvExport.build();
    if (built is Failure<LedgerCsvExport>) {
      setState(() => _status = localizedError(built.error));
      return;
    }
    final export = (built as Success<LedgerCsvExport>).value;
    await _run('مشاركة الملف', () async {
      try {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, export.fileName));
        await file.writeAsBytes(export.bytes, flush: true);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'تصدير حركات كروتك',
        );
        return 'تمت مشاركة ملف CSV.';
      } catch (error) {
        return localizedError(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          title: Text('الصيانة والتنظيف والتصدير', style: _titleStyle(context)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: NetSpacing.page,
                children: [
                  if (_error != null) _statusCard(context, _error!, isError: true),
                  _logsSection(context),
                  const SizedBox(height: NetSpacing.md),
                  _deepCleanSection(context),
                  const SizedBox(height: NetSpacing.md),
                  _exportSection(context),
                  if (_status != null) ...[
                    const SizedBox(height: NetSpacing.md),
                    _statusCard(context, _status!),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _logsSection(BuildContext context) {
    final size = _size;
    return _Section(
      title: 'تنظيف السجلات',
      subtitle: 'استعادة الرسائل المعلّقة وحذف السجلات المنتهية حسب سياسة '
          'الاحتفاظ. لا تُحذف أي حركة مالية.',
      children: [
        _InfoRow(label: 'معلّقة بحاجة لمعالجة', value: '$_pending'),
        _InfoRow(label: 'مرفوضة', value: '$_rejected'),
        _InfoRow(label: 'فاشلة', value: '$_failed'),
        _InfoRow(
          label: 'حجم قاعدة البيانات',
          value: size == null ? 'غير متاح' : size.logicalLabel,
        ),
        _InfoRow(
          label: 'مساحة قابلة للتحرير',
          value: size == null ? 'غير متاح' : size.reclaimableLabel,
        ),
        const SizedBox(height: NetSpacing.sm),
        _ActionButton(
          label: 'استعادة المعلّق',
          icon: Icons.restore_rounded,
          busy: _running == 'استعادة المعلّق',
          enabled: !_busy,
          onPressed: () => _run('استعادة المعلّق', _recoverPending),
        ),
        const SizedBox(height: NetSpacing.xs),
        _ActionButton(
          label: 'تنظيف السجلات المنتهية',
          icon: Icons.cleaning_services_rounded,
          busy: _running == 'تنظيف السجلات',
          enabled: !_busy,
          onPressed: () => _run('تنظيف السجلات', _purge),
        ),
      ],
    );
  }

  Widget _deepCleanSection(BuildContext context) {
    return _Section(
      title: 'التنظيف العميق',
      subtitle: LocalMaintenanceService.deepCleanSummaryAr,
      children: [
        _ActionButton(
          label: 'تنفيذ التنظيف العميق',
          icon: Icons.auto_fix_high_rounded,
          busy: _running == 'التنظيف العميق',
          enabled: !_busy,
          onPressed: () => _run('التنظيف العميق', _deepClean),
        ),
      ],
    );
  }

  Widget _exportSection(BuildContext context) {
    return _Section(
      title: 'تصدير السجل',
      subtitle: 'ملف CSV لكل الحركات بترميز عربي يفتح مباشرة في Excel، '
          'يُحفظ في مجلد التنزيلات ويمكن مشاركته.',
      children: [
        if (_exportRows != null)
          _InfoRow(label: 'آخر تصدير', value: '$_exportRows حركة'),
        if (_exportPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NetSpacing.xs),
            child: SelectableText(
              'الملف: $_exportPath',
              style: _bodyStyle(context),
            ),
          ),
        _ActionButton(
          label: 'تصدير ملف CSV',
          icon: Icons.upload_file_rounded,
          busy: _running == 'تصدير الملف',
          enabled: !_busy,
          onPressed: () => _run('تصدير الملف', _export),
        ),
        const SizedBox(height: NetSpacing.xs),
        _ActionButton(
          label: 'مشاركة آخر تصدير',
          icon: Icons.share_rounded,
          busy: _running == 'مشاركة الملف',
          enabled: !_busy,
          onPressed: _shareExport,
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, String text, {bool isError = false}) {
    return NetSurfaceCard(
      padding: const EdgeInsets.all(NetSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: NetSizes.iconSm,
            color: isError ? context.netColors.error : KayanPalette.of(context).primary,
          ),
          const SizedBox(width: NetSpacing.xs),
          Expanded(child: Text(text, style: _bodyStyle(context))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NetSurfaceCard(
      padding: const EdgeInsets.all(NetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: _titleStyle(context)),
          const SizedBox(height: NetSpacing.xxs),
          Text(subtitle, style: _bodyStyle(context)),
          const SizedBox(height: NetSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _bodyStyle(context))),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.busy,
    required this.enabled,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontFamily: 'Tajawal')),
    );
  }
}

TextStyle _titleStyle(BuildContext context) => TextStyle(
      fontFamily: 'Tajawal',
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: KayanPalette.of(context).textPrimary,
    );

TextStyle _bodyStyle(BuildContext context) => TextStyle(
      fontFamily: 'Tajawal',
      fontSize: 12.5,
      height: 1.5,
      color: KayanPalette.of(context).textSecondary,
    );
