import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/net/net_app_bar_title.dart';
import '../../widgets/net/net_surface_card.dart';

/// تنظيف عميق — VACUUM / ANALYZE مطابق فيديو المنتج.
class DeepCleanScreen extends StatefulWidget {
  const DeepCleanScreen({super.key});

  @override
  State<DeepCleanScreen> createState() => _DeepCleanScreenState();
}

class _DeepCleanScreenState extends State<DeepCleanScreen> {
  bool _running = false;
  String? _status;

  Future<void> _run() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = KayanPalette.of(ctx);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('بدء التنظيف العميق؟', style: TextStyle(fontFamily: 'Tajawal')),
            content: Text(
              'سيُعاد بناء فهارس قاعدة البيانات. لا تغلق التطبيق أثناء التنفيذ.',
              style: TextStyle(fontFamily: 'Tajawal', height: 1.5, color: palette.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('بدء'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _running = true;
      _status = null;
    });
    final r = await AppScope.of(context).maintenanceService.runDeepClean();
    if (!mounted) return;
    setState(() {
      _running = false;
      if (r is Failure) {
        _status = (r as Failure).error.message;
      } else {
        final ms = (r as Success).value.durationMs;
        _status = 'اكتمل التنظيف العميق خلال ${ms}ms';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

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
            icon: Icons.cleaning_services_rounded,
            title: 'تنظيف عميق',
            subtitle: 'إعادة بناء الفهارس وتصفير السجلات',
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(NetSpacing.lg, NetSpacing.md, NetSpacing.lg, NetSpacing.lg),
                children: [
                  NetSurfaceCard(
                    padding: const EdgeInsets.all(NetSpacing.xl),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEF3C7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_fix_high_rounded, size: 32, color: Color(0xFFD97706)),
                        ),
                        const SizedBox(height: NetSpacing.md),
                        Text(
                          'تحسين أداء قاعدة البيانات',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: NetSpacing.sm),
                        Text(
                          'هذه العملية ستقوم بإعادة بناء فهارس قاعدة البيانات بالكامل وتحديث إحصائيات العمليات، مما يؤدي إلى تسريع التطبيق وتخفيض استهلاك الذاكرة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 14,
                            height: 1.55,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(NetSpacing.md),
                    decoration: BoxDecoration(
                      color: net.errorContainer,
                      borderRadius: NetRadii.mdAll,
                      border: Border.all(color: net.error.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: net.error),
                        const SizedBox(width: NetSpacing.sm),
                        Expanded(
                          child: Text(
                            'تنبيه: يجب عدم إغلاق التطبيق أثناء تنفيذ هذه العملية، حيث قد يستغرق الأمر بضع دقائق حسب حجم بياناتك.',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: net.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: NetSpacing.md),
                    Text(
                      _status!,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        color: palette.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(NetSpacing.lg, 0, NetSpacing.lg, NetSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _running ? null : _run,
                    icon: _running
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _running ? 'جاري التنظيف العميق…' : 'بدء التنظيف العميق',
                      style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
