import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/system_capability.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_app_bar_title.dart';

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
    final net = context.netColors;
    switch (level) {
      case SystemHealthLevel.ready:
        return net.available;
      case SystemHealthLevel.warning:
        return net.warning;
      case SystemHealthLevel.critical:
        return net.rejected;
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
          title: const NetAppBarTitle(
            icon: Icons.health_and_safety_rounded,
            title: 'فحص وتشخيص النظام',
            subtitle: 'جاهزية الأذونات والتشغيل',
          ),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'إعادة الفحص',
              onPressed: _loading ? null : _runCheck,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
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
      color: palette.primary,
      child: ListView(
        padding: NetSpacing.screen,
        children: [
          Container(
            padding: const EdgeInsets.all(NetSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: palette.isDark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(NetRadii.md),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  level == SystemHealthLevel.ready
                      ? Icons.verified_rounded
                      : level == SystemHealthLevel.warning
                          ? Icons.warning_amber_rounded
                          : Icons.error_outline_rounded,
                  color: color,
                  size: 34,
                ),
                const SizedBox(width: NetSpacing.sm),
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
          const SizedBox(height: NetSpacing.lg),
          _section(
            palette: palette,
            title: 'إمكانيات حرجة',
            subtitle: 'بدونها تتوقف الأتمتة أو تفشل معالجة الرسائل',
            items: snap.of(CapabilitySeverity.critical),
            tone: context.netColors.rejected,
          ),
          _section(
            palette: palette,
            title: 'إمكانيات مستحسنة',
            subtitle: 'تحسن الاستقرار على أجهزة الشركات المصنّعة',
            items: snap.of(CapabilitySeverity.recommended),
            tone: context.netColors.warning,
          ),
          _section(
            palette: palette,
            title: 'إمكانيات اختيارية',
            subtitle: 'ميزات إضافية غير إلزامية للتشغيل الأساسي',
            items: snap.of(CapabilitySeverity.optional),
            tone: palette.primary,
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
        const SizedBox(height: NetSpacing.sm),
        ...items.map((c) => _capCard(c, palette)),
        const SizedBox(height: NetSpacing.lg),
      ],
    );
  }

  Widget _capCard(SystemCapability cap, KayanPalette palette) {
    final ok = cap.isOk;
    final busy = _busyId == cap.id;
    final net = context.netColors;
    return NetSurfaceCard(
      margin: const EdgeInsets.only(bottom: NetSpacing.sm),
      padding: NetSpacing.cardTight,
      borderColor: ok ? net.available.withValues(alpha: 0.55) : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: ok ? net.available : net.rejected,
                size: 22,
              ),
              const SizedBox(width: NetSpacing.sm),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: ok ? net.availableContainer : net.rejectedContainer,
                  borderRadius: BorderRadius.circular(NetRadii.xs),
                ),
                child: Text(
                  ok ? 'مفعّل' : 'غير مفعّل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ok ? net.available : net.rejected,
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
                    : const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(
                  cap.actionLabel!,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
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
