import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';

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

  /// هل إشعارات الهاتف مسموحة؟ null = لا يمكن الفحص (غير أندرويد/خطأ).
  bool? _notificationsAllowed;

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
    final allowed = await c.stockAlertNotifier.hasPermission();
    if (!mounted) return;
    setState(() {
      _ctrl.text = '$value';
      _notificationsAllowed = allowed;
      _loading = false;
    });
  }

  /// يطلب إذن الإشعارات عند الحاجة (الإشعار الحي لا يظهر بدونه).
  Future<void> _requestNotifications() async {
    final c = AppScope.of(context);
    final granted = await c.stockAlertNotifier.requestPermission();
    if (!mounted) return;
    setState(() => _notificationsAllowed = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لم يُمنح إذن الإشعارات — فعّله من إعدادات التطبيق ليظهر تنبيه المخزون',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
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
    final net = context.netColors;
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
                    'سيتم تنبيهك في لوحة التحكم، وبإشعار حي في شريط إشعارات الهاتف يبقى ظاهراً حتى إعادة تعبئة المخزون، عندما يقل المتاح لأي فئة كروت عن هذه العتبة.',
                    style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  if (_notificationsAllowed != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _notificationsAllowed! ? kayan.surfaceVariant : net.warningContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _notificationsAllowed! ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                            size: 20,
                            color: _notificationsAllowed! ? kayan.primary : net.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _notificationsAllowed!
                                  ? 'إشعارات الهاتف مسموحة — سيظهر تنبيه المخزون الحي في شريط الإشعارات.'
                                  : 'إشعارات الهاتف ممنوعة، لذلك لن يظهر تنبيه المخزون في شريط الإشعارات.',
                              style: TextStyle(fontFamily: 'Tajawal', fontSize: 12.5, height: 1.45, color: kayan.textPrimary),
                            ),
                          ),
                          if (!_notificationsAllowed!)
                            TextButton(
                              onPressed: _requestNotifications,
                              child: const Text('تفعيل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
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
