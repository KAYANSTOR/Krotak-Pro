import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/async_views.dart';

/// صيانة السجلات: حجم الرسائل + استعادة المعلّق + تنظيف ذكي.
class CleanLogsScreen extends StatefulWidget {
  const CleanLogsScreen({super.key});

  @override
  State<CleanLogsScreen> createState() => _CleanLogsScreenState();
}

class _CleanLogsScreenState extends State<CleanLogsScreen> {
  bool _loading = true;
  String? _error;
  int _pending = 0;
  int _rejected = 0;
  int _failed = 0;
  String? _status;
  bool _recovering = false;
  bool _purging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final pending = await c.messages.pendingProcessing();
    final rejected = await c.messages.listByStatus(MessageProcessingStatus.rejected);
    final failed = await c.messages.listByStatus(MessageProcessingStatus.failed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (pending is Failure || rejected is Failure || failed is Failure) {
        _error = 'تعذر قراءة السجلات';
        return;
      }
      _pending = (pending as Success).value.length;
      _rejected = (rejected as Success).value.length;
      _failed = (failed as Success).value.length;
    });
  }

  Future<void> _recover() async {
    setState(() => _recovering = true);
    final c = AppScope.of(context);
    final r = await c.recoveryService.recoverPending();
    if (!mounted) return;
    setState(() {
      _recovering = false;
      if (r is Success) {
        final report = (r as Success).value;
        _status =
            'استعادة: معالَج=${report.processed} فاشل=${report.failed}';
      } else {
        _status = (r as Failure).error.message;
      }
    });
    await _load();
  }

  Future<void> _purge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'تأكيد التنظيف الذكي',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'سيُحذف فقط: الرسائل المرفوضة (>30 يوم)، المكتملة (>3 أيام)، والمستنفدة (>30 يوم).\n'
            'لن تُمس المبيعات أو القيود المحاسبية أو الكروت.\n\n'
            'هل تريد المتابعة؟',
            style: TextStyle(fontFamily: 'Tajawal', height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تنظيف', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _purging = true);
    final c = AppScope.of(context);
    final r = await c.maintenanceService.purgeExpiredMessages();
    if (!mounted) return;
    setState(() {
      _purging = false;
      if (r is Success) {
        final report = (r as Success).value;
        _status =
            'تنظيف: مرفوض=${report.deletedRejected} مكتمل=${report.deletedProcessed} مستنفد=${report.deletedFailedMax}';
      } else {
        _status = (r as Failure).error.message;
      }
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          title: Text(
            'تنظيف السجلات',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          backgroundColor: palette.appBackground,
          foregroundColor: palette.textPrimary,
          elevation: 0,
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري قراءة حجم السجلات…')
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    color: KayanColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Text(
                          'حجم الرسائل حسب الحالة',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _statCard(
                                palette,
                                title: 'معلّقة',
                                value: '$_pending',
                                color: const Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard(
                                palette,
                                title: 'مرفوضة',
                                value: '$_rejected',
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard(
                                palette,
                                title: 'فاشلة',
                                value: '$_failed',
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: palette.border),
                          ),
                          child: Text(
                            'التنظيف الذكي يحذف فقط: المرفوض (>30 يوم)، المكتمل (>3 أيام)، والمستنفد (>30 يوم). لا يمس المبيعات أو القيود المحاسبية.',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 13,
                              height: 1.45,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: KayanColors.primary,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: _recovering ? null : _recover,
                          icon: _recovering
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.restore),
                          label: Text(
                            _recovering ? 'جاري الاستعادة…' : 'استعادة المعلّق',
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: (_purging || _recovering) ? null : _purge,
                          icon: _purging
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_sweep_outlined),
                          label: Text(
                            _purging ? 'جاري التنظيف…' : 'تنظيف السجلات المنتهية',
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_status != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _status!,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _statCard(
    KayanPalette palette, {
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
