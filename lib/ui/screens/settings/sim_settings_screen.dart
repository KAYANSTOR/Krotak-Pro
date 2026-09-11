import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class SimSettingsScreen extends StatefulWidget {
  const SimSettingsScreen({super.key});
  @override
  State<SimSettingsScreen> createState() => _SimSettingsScreenState();
}

class _SimSettingsScreenState extends State<SimSettingsScreen> {
  bool _loading = true;
  String? _error;
  String _slot = '0';
  bool _listen = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final c = AppScope.of(context);
    final slot = await c.settings.find(SettingKeys.preferredSimSlot);
    final listen = await c.settings.find(SettingKeys.smsListenEnabled);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (slot is Failure || listen is Failure) {
        _error = 'تعذر قراءة الإعدادات';
        return;
      }
      final s = (slot as Success).value;
      final l = (listen as Success).value;
      if (s != null) _slot = s.value;
      if (l != null) _listen = l.value == 'true';
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = AppScope.of(context);
    final now = c.clock.now();
    await c.settings.save(AppSetting(key: SettingKeys.preferredSimSlot, value: _slot, updatedAt: now));
    await c.settings.save(AppSetting(key: SettingKeys.smsListenEnabled, value: _listen.toString(), updatedAt: now));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ محليًا', style: TextStyle(fontFamily: 'Tajawal'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الشريحة')),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('تُحفظ محليًا (offline-first).', style: TextStyle(fontFamily: 'Tajawal')),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _slot,
                      decoration: const InputDecoration(labelText: 'فتحة الشريحة المفضلة', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: '0', child: Text('SIM 1')),
                        DropdownMenuItem(value: '1', child: Text('SIM 2')),
                      ],
                      onChanged: (v) => setState(() => _slot = v ?? '0'),
                    ),
                    SwitchListTile(
                      title: const Text('استماع لرسائل SMS', style: TextStyle(fontFamily: 'Tajawal')),
                      value: _listen,
                      onChanged: (v) => setState(() => _listen = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('حفظ'),
                    ),
                  ],
                ),
    );
  }
}
