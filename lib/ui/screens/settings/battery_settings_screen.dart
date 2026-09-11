import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

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
    await c.settings.save(AppSetting(key: SettingKeys.batteryOptimizationAcknowledged, value: _ack.toString(), updatedAt: c.clock.now()));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ', style: TextStyle(fontFamily: 'Tajawal'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البطارية')),
      body: _loading
          ? const AsyncLoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('تذكير offline باستثناء تحسين البطارية لضمان استلام SMS.', style: TextStyle(fontFamily: 'Tajawal')),
                SwitchListTile(title: const Text('تم الاطلاع', style: TextStyle(fontFamily: 'Tajawal')), value: _ack, onChanged: (v) => setState(() => _ack = v)),
                FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
              ],
            ),
    );
  }
}
