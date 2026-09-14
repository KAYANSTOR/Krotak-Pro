import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';

/// تنبيهات انخفاض مخزون الكروت — عتبة التنبيه (افتراضي 10 كما في الفيديو).
class LowStockSettingsScreen extends StatefulWidget {
  const LowStockSettingsScreen({super.key});

  @override
  State<LowStockSettingsScreen> createState() => _LowStockSettingsScreenState();
}

class _LowStockSettingsScreenState extends State<LowStockSettingsScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final r = await c.settings.find(SettingKeys.lowStockThreshold);
    final raw = r is Success<AppSetting?> ? r.value?.value : null;
    final value = SettingInt.read(raw, defaultValue: SettingDefaults.lowStockThreshold);
    if (!mounted) return;
    setState(() {
      _ctrl.text = '$value';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == null || n < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقمًا صحيحًا ≥ 0', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    setState(() => _saving = true);
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.lowStockThreshold,
        value: '$n',
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          title: const Text('تنبيهات انخفاض المخزون', style: TextStyle(fontFamily: 'Tajawal')),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'سيتم تنبيهك في لوحة التحكم عندما يقل المخزون المتاح لأي فئة كروت عن هذه العتبة.',
                    style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'الحد الأدنى (عدد الكروت)',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, color: kayan.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '${SettingDefaults.lowStockThreshold}',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
      ),
    );
  }
}
