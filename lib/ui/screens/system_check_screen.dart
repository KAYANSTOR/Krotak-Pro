import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/system_capability.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../widgets/async_views.dart';

/// مركز فحص وتشخيص النظام — مطابق دليل 1.0.9 + ثيم Kayan التكيّفي.
class SystemCheckScreen extends StatefulWidget {
  const SystemCheckScreen({super.key});

  @override
  State<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends State<SystemCheckScreen> {
  bool _loading = true;
  String? _error;
  SystemHealthSnapshot? _snapshot;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  Future<void> _runCheck() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AppScope.of(context).systemHealth.check();
    if (!mounted) return;
    if (r is Failure<SystemHealthSnapshot>) {
      setState(() {
        _loading = false;
        _error = r.error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _snapshot = (r as Success<SystemHealthSnapshot>).value;
    });
  }

  Future<void> _act(SystemCapability cap) async {
    final action = cap.settingsAction;
    if (action == null) return;
    setState(() => _busyId = cap.id);
    final r = await AppScope.of(context).systemHealth.runAction(action);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (r is Success<SystemHealthSnapshot>) {
      setState(() => _snapshot = r.value);
    }
  }

  Color _levelColor(SystemHealthLevel level) {
    switch (level) {
      case SystemHealthLevel.ready:
        return const Color(0xFF059669);
      case SystemHealthLevel.warning:
        return const Color(0xFFD97706);
      case SystemHealthLevel.critical:
        return const Color(0xFFDC2626);
    }
  }

  String _levelTitle(SystemHealthLevel level) {
    switch (level) {
      case SystemHealthLevel.ready:
        return 'جاهز تمامًا';
      case SystemHealthLevel.warning:
        return 'تحذير جاهزية';
      case SystemHealthLevel.critical:
        return 'خلل في صلاحية حرجة';
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
          title: Text(
            'فحص وتشخيص النظام',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          backgroundColor: palette.appBackground,
          foregroundColor: palette.textPrimary,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'إعادة الفحص',
              onPressed: _loading ? null : _runCheck,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري فحص الصلاحيات والخدمات…')
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _runCheck)
                : _buildBody(palette),
      ),
    );
  }

  Widget _buildBody(KayanPalette palette) {
    final snap = _snapshot!;
    final level = snap.level;
    final color = _levelColor(level);

    return RefreshIndicator(
      onRefresh: _runCheck,
      color: KayanColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: palette.isDark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  level == SystemHealthLevel.ready
                      ? Icons.verified_user
                      : level == SystemHealthLevel.warning
                          ? Icons.warning_amber_rounded
                          : Icons.error_outline,
                  color: color,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _levelTitle(level),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        snap.bannerMessage,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          height: 1.35,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section(
            palette: palette,
            title: 'إمكانيات حرجة',
            subtitle: 'بدونها تتوقف الأتمتة أو تفشل معالجة الرسائل',
            items: snap.of(CapabilitySeverity.critical),
            tone: const Color(0xFFDC2626),
          ),
          _section(
            palette: palette,
            title: 'إمكانيات مستحسنة',
            subtitle: 'تحسن الاستقرار على أجهزة الشركات المصنّعة',
            items: snap.of(CapabilitySeverity.recommended),
            tone: const Color(0xFFD97706),
          ),
          _section(
            palette: palette,
            title: 'إمكانيات اختيارية',
            subtitle: 'ميزات إضافية غير إلزامية للتشغيل الأساسي',
            items: snap.of(CapabilitySeverity.optional),
            tone: const Color(0xFF0F766E),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required KayanPalette palette,
    required String title,
    required String subtitle,
    required List<SystemCapability> items,
    required Color tone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: tone,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((c) => _capCard(c, palette)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _capCard(SystemCapability cap, KayanPalette palette) {
    final ok = cap.isOk;
    final busy = _busyId == cap.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ok
              ? const Color(0xFF059669).withValues(alpha: palette.isDark ? 0.45 : 1)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.cancel_outlined,
                color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cap.title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ok
                      ? const Color(0xFF059669).withValues(alpha: palette.isDark ? 0.2 : 0.08)
                      : const Color(0xFFDC2626).withValues(alpha: palette.isDark ? 0.2 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ok ? 'مفعّل' : 'غير مفعّل',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            cap.detail,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          if (!ok && cap.actionLabel != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KayanColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: busy ? null : () => _act(cap),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new, size: 16),
                label: Text(
                  cap.actionLabel!,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
