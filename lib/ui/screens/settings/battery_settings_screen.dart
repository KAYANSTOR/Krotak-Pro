import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

class BatterySettingsScreen extends StatefulWidget {
  const BatterySettingsScreen({super.key});

  @override
  State<BatterySettingsScreen> createState() => _BatterySettingsScreenState();
}

class _BatterySettingsScreenState extends State<BatterySettingsScreen> {
  bool _loading = true;
  bool _ack = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await AppScope.of(context).settings.find(SettingKeys.batteryOptimizationAcknowledged);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<AppSetting?> && r.value != null) {
        _ack = r.value!.value == 'true';
      }
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
      const SnackBar(content: Text('تم الحفظ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البطارية')),
      body: _loading
          ? const AsyncLoadingView(skeleton: true, skeletonCount: 2)
          : ListView(
              padding: NetSpacing.screen,
              children: [
                const NetInlineNotice(
                  message:
                      'لضمان استلام SMS في الخلفية، يُفضَّل استثناء التطبيق من تحسين البطارية على الجهاز. هذا التذكير يُحفظ محليًا فقط.',
                ),
                const SizedBox(height: NetSpacing.lg),
                NetSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile.adaptive(
                    contentPadding: NetSpacing.row,
                    title: Text(
                      'تم الاطلاع على توصية البطارية',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KayanPalette.of(context).textPrimary,
                      ),
                    ),
                    value: _ack,
                    activeTrackColor: KayanPalette.of(context).primary,
                    onChanged: (v) => setState(() => _ack = v),
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('حفظ'),
                ),
              ],
            ),
    );
  }
}
