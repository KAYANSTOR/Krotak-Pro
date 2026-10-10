import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/device_verification_gate.dart';
import '../../../domain/entities/background_diagnostics.dart';
import '../../../domain/services/local_device_verification_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../../errors/user_facing_error_localizer.dart';

class DeviceVerificationScreen extends StatefulWidget {
  const DeviceVerificationScreen({super.key});

  @override
  State<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  bool _loading = true;
  String? _error;
  DeviceVerificationSnapshot _snapshot = const DeviceVerificationSnapshot(statuses: {});

  /// WP-9 — تشخيص الخلفية: أسباب إنهاء العملية وأحداث خدمة الحفاظ.
  BackgroundDiagnostics _background = const BackgroundDiagnostics();

  LocalDeviceVerificationService _service() {
    final c = AppScope.of(context);
    return LocalDeviceVerificationService(settings: c.settings, clock: c.clock);
  }

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
    final result = await _service().load();
    if (!mounted) return;
    if (result is Failure<DeviceVerificationSnapshot>) {
      setState(() {
        _loading = false;
        _error = localizedError(result.error);
      });
      return;
    }
    setState(() {
      _loading = false;
      _snapshot = (result as Success<DeviceVerificationSnapshot>).value;
    });
    await _loadBackground();
  }

  /// يقرأ تشخيص الخلفية من الجهة الأصلية (بلا إسقاط الشاشة عند فشله).
  Future<void> _loadBackground() async {
    final c = AppScope.of(context);
    final result = await c.systemHealth.backgroundDiagnostics();
    if (!mounted) return;
    if (result is Success<BackgroundDiagnostics>) {
      setState(() => _background = result.value);
    }
  }

  Future<void> _set(String id, DeviceVerificationStatus status) async {
    String? note;
    if (status == DeviceVerificationStatus.passed &&
        DeviceVerificationCatalog.measurementGateIds.contains(id)) {
      note = await _askNote(id);
      if (!mounted) return;
      if (note == null || note.trim().isEmpty) return;
    }
    final result = await _service().mark(gateId: id, status: status, note: note);
    if (!mounted) return;
    if (result is Success<DeviceVerificationSnapshot>) {
      setState(() => _snapshot = result.value);
    }
  }

  Future<void> _copyPack() async {
    final pack = _service().exportEvidencePack(_snapshot);
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(pack)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _snapshot.readyForRelease
              ? 'تم نسخ حزمة الأدلة — جاهزة الإصدار مكتملة على الجهاز'
              : 'تم نسخ حزمة الأدلة (البوابات غير مكتملة بعد)',
        ),
      ),
    );
  }

  Future<String?> _askNote(String id) async {
    final controller = TextEditingController();
    final title = id == 'bulk_import' ? 'قياس الاستيراد' : 'قياس البث';
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'مثال: 80 صف مقبول في 1.4 ثانية / 11 رسالة في 9 ثوان',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحقق الجهاز'),
          actions: [
            IconButton(
              tooltip: 'نسخ حزمة الأدلة',
              onPressed: _loading ? null : _copyPack,
              icon: const Icon(Icons.copy_all_outlined),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: NetSpacing.screen,
                    children: [
                      NetSurfaceCard(
                        borderColor: _snapshot.readyForRelease
                            ? context.netColors.premium.withValues(alpha: 0.45)
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (_snapshot.readyForRelease) ...[
                                  Icon(
                                    Icons.workspace_premium_rounded,
                                    size: 18,
                                    color: context.netColors.premium,
                                  ),
                                  const SizedBox(width: NetSpacing.xs),
                                ],
                                Expanded(
                                  child: Text(
                                    'بوابات الإنتاج — ${_snapshot.passedCount}/${_snapshot.total} مؤكدة على جهاز حقيقي',
                                    style: TextStyle(
                                      fontFamily: NetTypography.family,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: NetSpacing.xs),
                            Text(
                              _snapshot.readyForRelease
                                  ? 'جاهز للإصدار: كل البوابات مُرّرت مع أدلة قياس.'
                                  : 'أكمل البوابات المتبقية على جهاز حقيقي قبل الإصدار.',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12.5,
                                height: 1.4,
                                color: _snapshot.readyForRelease
                                    ? context.netColors.premium
                                    : palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SettingsSectionHeader(title: 'البوابات'),
                      for (final item in DeviceVerificationCatalog.items)
                        _GateCard(
                          item: item,
                          status: _snapshot.of(item.id),
                          evidence: _snapshot.evidenceOf(item.id),
                          onPassed: () => _set(item.id, DeviceVerificationStatus.passed),
                          onBlocked: () => _set(item.id, DeviceVerificationStatus.blocked),
                          onReset: () => _set(item.id, DeviceVerificationStatus.pending),
                        ),
                      const SettingsSectionHeader(title: 'تشخيص الخلفية'),
                      _BackgroundDiagnosticsCard(diagnostics: _background),
                    ],
                  ),
      ),
    );
  }
}

/// WP-9 — بطاقة تشخيص الخلفية: أسباب إنهاء العملية وأحداث خدمة الحفاظ
/// بأسماء عربية (بلا أي رمز برمجي)، وتنص على أن تحقق 12 ساعة يبقى يدويًا.
class _BackgroundDiagnosticsCard extends StatelessWidget {
  const _BackgroundDiagnosticsCard({required this.diagnostics});

  final BackgroundDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    return NetSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'آخر أسباب إنهاء التطبيق وأحداث خدمة الحفاظ في الخلفية.',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12.5,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          if (diagnostics.targetSdk != null) ...[
            const SizedBox(height: NetSpacing.xs),
            _DiagnosticsRow(
              label: 'مستوى الاستهداف',
              value: '${diagnostics.targetSdk}',
            ),
          ],
          if (diagnostics.exitReasons.isNotEmpty) ...[
            const SizedBox(height: NetSpacing.sm),
            Text(
              'أسباب الإنهاء',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            for (final reason in diagnostics.exitReasons.take(6))
              _DiagnosticsRow(
                label: _formatStamp(reason.at),
                value: reason.code.arabicLabel,
              ),
          ],
          if (diagnostics.serviceEvents.isNotEmpty) ...[
            const SizedBox(height: NetSpacing.sm),
            Text(
              'أحداث خدمة الحفاظ على التسليم',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            for (final event in diagnostics.serviceEvents.take(8))
              _DiagnosticsRow(
                label: _formatStamp(event.at),
                value: event.detail.isEmpty
                    ? event.code.arabicLabel
                    : '${event.code.arabicLabel} — ${event.detail}',
              ),
          ],
          if (diagnostics.isEmpty) ...[
            const SizedBox(height: NetSpacing.xs),
            Text(
              'لا توجد بيانات بعد — تظهر بعد أول تشغيل للخدمة في الخلفية.',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: NetSpacing.sm),
          Text(
            'تحقق العمل 12 ساعة متواصلة مع قفل الشاشة يبقى فحصًا يدويًا على جهاز حقيقي — وقد يوقف النظام التطبيق لأسباب خارج سيطرة التطبيق (إيقاف يدوي أو توفير بطارية من الشركة المصنّعة).',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              height: 1.4,
              color: net.pending,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatStamp(DateTime at) {
    final day = at.day.toString().padLeft(2, '0');
    final month = at.month.toString().padLeft(2, '0');
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$day/$month ${hour}:$minute';
  }
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: NetSpacing.xs),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: NetTypography.family,
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

class _GateCard extends StatelessWidget {
  const _GateCard({
    required this.item,
    required this.status,
    required this.evidence,
    required this.onPassed,
    required this.onBlocked,
    required this.onReset,
  });

  final DeviceVerificationItem item;
  final DeviceVerificationStatus status;
  final DeviceGateEvidence evidence;
  final VoidCallback onPassed;
  final VoidCallback onBlocked;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final (label, tone, container) = switch (status) {
      DeviceVerificationStatus.passed => (
          'مؤكد',
          net.available,
          net.availableContainer,
        ),
      DeviceVerificationStatus.blocked => (
          'موقوف',
          net.rejected,
          net.rejectedContainer,
        ),
      DeviceVerificationStatus.pending => (
          'بانتظار الجهاز',
          net.warning,
          net.warningContainer,
        ),
    };
    return NetSurfaceCard(
      margin: const EdgeInsets.only(bottom: NetSpacing.sm),
      padding: NetSpacing.cardTight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
                  color: container,
                  borderRadius: BorderRadius.circular(NetRadii.xs),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.xs),
          Text(
            item.detail,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: NetSpacing.xxs),
          Text(
            item.phaseRef,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              color: palette.textTertiary,
            ),
          ),
          if (evidence.hasOperatorNote) ...[
            const SizedBox(height: NetSpacing.xs),
            Text(
              evidence.note!,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: NetSpacing.sm),
          Wrap(
            spacing: NetSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: onPassed,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('تم على الجهاز'),
              ),
              TextButton.icon(
                onPressed: onBlocked,
                icon: const Icon(Icons.block_rounded, size: 16),
                label: const Text('موقوف'),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('إعادة'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
