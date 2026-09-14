import 'package:flutter/material.dart';

import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../routing/app_routes.dart';
import '../system_check_screen.dart';
import 'low_stock_settings_screen.dart';
import 'sim_settings_screen.dart';

/// مركز الإعدادات — أقسام مطابقة للفيديو + فحص النظام 1.0.9.
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  bool _loading = true;
  String _networkName = SettingDefaults.networkName;
  bool _autoSms = SettingDefaults.smsAutoProcessingEnabled;
  bool _categoryOnly = SettingDefaults.processCategoryAmountsOnly;
  bool _oldMsgs = SettingDefaults.processOldMessagesOnResume;
  bool _salafni = SettingDefaults.salafniEnabled;
  ThemeMode _theme = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    Future<String?> v(String key) async {
      final r = await c.settings.find(key);
      return r is Success ? (r as dynamic).value?.value as String? : null;
    }

    final name = await v(SettingKeys.networkName);
    final auto = await v(SettingKeys.smsAutoProcessingEnabled);
    final cat = await v(SettingKeys.processCategoryAmountsOnly);
    final old = await v(SettingKeys.processOldMessagesOnResume);
    final sal = await v(SettingKeys.salafniEnabled);
    final theme = await v(SettingKeys.themeMode);

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (name != null && name.trim().isNotEmpty) _networkName = name.trim();
      _autoSms = SettingBool.read(auto, defaultValue: SettingDefaults.smsAutoProcessingEnabled);
      _categoryOnly = SettingBool.read(cat, defaultValue: SettingDefaults.processCategoryAmountsOnly);
      _oldMsgs = SettingBool.read(old, defaultValue: SettingDefaults.processOldMessagesOnResume);
      _salafni = SettingBool.read(sal, defaultValue: SettingDefaults.salafniEnabled);
      switch ((theme ?? SettingDefaults.themeMode).toLowerCase()) {
        case 'dark':
          _theme = ThemeMode.dark;
        case 'light':
          _theme = ThemeMode.light;
        default:
          _theme = ThemeMode.system;
      }
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(key: key, value: value.toString(), updatedAt: c.clock.now()),
    );
  }

  Future<void> _saveName(String name) async {
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(key: SettingKeys.networkName, value: name.trim(), updatedAt: c.clock.now()),
    );
    setState(() => _networkName = name.trim().isEmpty ? SettingDefaults.networkName : name.trim());
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    final c = AppScope.of(context);
    final value = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await c.settings.save(
      AppSetting(key: SettingKeys.themeMode, value: value, updatedAt: c.clock.now()),
    );
    c.themeModeNotifier.value = mode;
    setState(() => _theme = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _sectionTitle('النظام'),
          _card([
            ListTile(
              title: const Text('اسم الشبكة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              subtitle: Text(_networkName, style: const TextStyle(fontFamily: 'Tajawal')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final ctrl = TextEditingController(text: _networkName);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('اسم الشبكة', style: TextStyle(fontFamily: 'Tajawal')),
                    content: TextField(controller: ctrl, style: const TextStyle(fontFamily: 'Tajawal')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal'))),
                    ],
                  ),
                );
                if (ok == true) await _saveName(ctrl.text);
                ctrl.dispose();
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('معالجة SMS تلقائيًا', style: TextStyle(fontFamily: 'Tajawal')),
              value: _autoSms,
              onChanged: (v) async {
                setState(() => _autoSms = v);
                await _saveBool(SettingKeys.smsAutoProcessingEnabled, v);
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('معالجة مبالغ الفئات فقط', style: TextStyle(fontFamily: 'Tajawal')),
              value: _categoryOnly,
              onChanged: (v) async {
                setState(() => _categoryOnly = v);
                await _saveBool(SettingKeys.processCategoryAmountsOnly, v);
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('معالجة الرسائل القديمة عند الاستئناف', style: TextStyle(fontFamily: 'Tajawal')),
              value: _oldMsgs,
              onChanged: (v) async {
                setState(() => _oldMsgs = v);
                await _saveBool(SettingKeys.processOldMessagesOnResume, v);
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('سلفني', style: TextStyle(fontFamily: 'Tajawal')),
              value: _salafni,
              onChanged: (v) async {
                setState(() => _salafni = v);
                await _saveBool(SettingKeys.salafniEnabled, v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF0F766E)),
              title: const Text('حد تنبيه انخفاض المخزون', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LowStockSettingsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sim_card_outlined, color: Color(0xFF0F766E)),
              title: const Text('إعدادات شرائح الاتصال', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              subtitle: const Text('قراءة / إرسال / Auto-Failover', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SimSettingsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined, color: Color(0xFFDC2626)),
              title: const Text('فحص وتشخيص النظام', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
              subtitle: const Text('صلاحيات حرجة · مستحسنة · اختيارية', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SystemCheckScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('المظهر'),
          _card([
            RadioListTile<ThemeMode>(
              title: const Text('فاتح', style: TextStyle(fontFamily: 'Tajawal')),
              value: ThemeMode.light,
              groupValue: _theme,
              onChanged: (v) => v == null ? null : _saveTheme(v),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('داكن', style: TextStyle(fontFamily: 'Tajawal')),
              value: ThemeMode.dark,
              groupValue: _theme,
              onChanged: (v) => v == null ? null : _saveTheme(v),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('حسب النظام', style: TextStyle(fontFamily: 'Tajawal')),
              value: ThemeMode.system,
              groupValue: _theme,
              onChanged: (v) => v == null ? null : _saveTheme(v),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('العمليات والمراجعة'),
          _card([
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('الرسائل المعلّقة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => AppRoutes.openPendingMessages(context),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('الرسائل الفاشلة / إعادة المحاولة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => AppRoutes.openFailedMessages(context),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('الرسائل المرفوضة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => AppRoutes.openRejectedMessages(context),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('الترخيص والنسخ'),
          _card([
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('الترخيص', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
              subtitle: const Text('حالة الترخيص وربط الجهاز', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('شاشة الترخيص متاحة من مسار الترخيص', style: TextStyle(fontFamily: 'Tajawal'))),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF0F766E),
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(children: children),
      );
}

// local import helper for Result without full path clash
import '../../../core/result.dart';
