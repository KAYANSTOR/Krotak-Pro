import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../platform/system_diagnostics_bridge.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

/// شاشة البطارية + التحقق الميداني (المرحلة R4).
class BatterySettingsScreen extends StatefulWidget {
  const BatterySettingsScreen({super.key});

  @override
  State<BatterySettingsScreen> createState() => _BatterySettingsScreenState();
}

class _BatterySettingsScreenState extends State<BatterySettingsScreen> {
  bool _loading = true;
  bool _ack = false;
  bool _saving = false;
  bool? _batteryIgnored;
  bool? _notificationAccess;
  final _diag = SystemDiagnosticsBridge();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final r = await c.settings.find(SettingKeys.batteryOptimizationAcknowledged);
    Map<String, Object?> probe = const {};
    try {
      probe = await _diag.probe();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<AppSetting?> && r.value != null) {
        _ack = r.value!.value == 'true';
      }
      _batteryIgnored = probe['batteryOptimizationIgnored'] == true;
      _notificationAccess = probe['notificationAccess'] == true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(
        key: SettingKeys.batteryOptimizationAcknowledged,
        value: _ack.toString(),
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم الحفظ', style: TextStyle(fontFamily: 'Tajawal')),
      ),
    );
  }

  Widget _statusRow(String title, bool? ok) {
    final palette = KayanPalette.of(context);
    final label = ok == null ? 'غير معروف' : (ok ? 'مفعّل' : 'غير مفعّل');
    final color = ok == null
        ? palette.textSecondary
        : (ok ? Colors.green.shade700 : Colors.red.shade700);
    return ListTile(
      contentPadding: NetSpacing.row,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      trailing: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'البطارية والتشغيل في الخلفية',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث الحالة',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 3)
            : ListView(
                padding: NetSpacing.screen,
                children: [
                  const NetInlineNotice(
                    message:
                        'لضمان استلام SMS والإشعارات في الخلفية: استثنِ NET من تحسين '
                        'البطارية، وفعّل التشغيل التلقائي على أجهزة الشركات. '
                        'Force-stop يوقف الاستقبال حتى يُفتح التطبيق يدوياً.',
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Text(
                    'حالة أندرويد الفعلية',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.sm),
                  NetSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _statusRow('استثناء تحسين البطارية', _batteryIgnored),
                        const Divider(height: 1),
                        _statusRow('وصول إشعارات المحافظ', _notificationAccess),
                      ],
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _diag.openBatteryOptimization();
                          await Future<void>.delayed(const Duration(seconds: 1));
                          await _load();
                        },
                        icon: const Icon(Icons.battery_saver_outlined),
                        label: const Text(
                          'إعدادات البطارية',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _diag.openAutoStartSettings();
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text(
                          'تشغيل تلقائي OEM',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _diag.openNotificationAccess();
                          await Future<void>.delayed(const Duration(seconds: 1));
                          await _load();
                        },
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text(
                          'إذن الإشعارات',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  Text(
                    'قائمة التحقق الميداني (R4)',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.sm),
                  const NetSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1) استثناء البطارية = مفعّل في الحالة أعلاه.',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '2) التشغيل التلقائي مفعّل يدوياً على جهازك (شاومي/هواوي/أوبو…).',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '3) SMS وارد والتطبيق في الخلفية → يُعالج دون فتح يدوي.',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '4) بعد إعادة تشغيل الهاتف (بدون Force-stop) → تصل رسالة وتُعالج.',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '5) لا تستخدم «إيقاف إجباري» على NET أثناء التشغيل اليومي.',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  NetSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile.adaptive(
                      contentPadding: NetSpacing.row,
                      title: Text(
                        'أقرّ بأنني راجعت توصيات البطارية والتشغيل التلقائي',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      value: _ack,
                      activeTrackColor: palette.primary,
                      onChanged: (v) => setState(() => _ack = v),
                    ),
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text(
                      'حفظ',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
