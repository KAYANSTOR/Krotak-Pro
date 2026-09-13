import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../widgets/async_views.dart';

class SalafniTemplatesScreen extends StatefulWidget {
  const SalafniTemplatesScreen({super.key});

  @override
  State<SalafniTemplatesScreen> createState() => _SalafniTemplatesScreenState();
}

class _SalafniTemplatesScreenState extends State<SalafniTemplatesScreen> {
  bool _loading = true;
  final _accepted = TextEditingController(text: LocalAdvanceService.defaultAccepted);
  final _rejected = TextEditingController(text: LocalAdvanceService.defaultRejected);
  final _settled = TextEditingController(text: LocalAdvanceService.defaultSettled);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    setState(() => _loading = true);
    Future<String> read(String key, String fallback) async {
      final r = await c.settings.find(key);
      if (r is Success<AppSetting?> && r.value?.value.trim().isNotEmpty == true) return r.value!.value;
      return fallback;
    }
    _accepted.text = await read(SettingKeys.salafniAcceptedTemplate, LocalAdvanceService.defaultAccepted);
    _rejected.text = await read(SettingKeys.salafniRejectedTemplate, LocalAdvanceService.defaultRejected);
    _settled.text = await read(SettingKeys.salafniSettledTemplate, LocalAdvanceService.defaultSettled);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final c = AppScope.of(context);
    final values = <String, String>{
      SettingKeys.salafniAcceptedTemplate: _accepted.text.trim(),
      SettingKeys.salafniRejectedTemplate: _rejected.text.trim(),
      SettingKeys.salafniSettledTemplate: _settled.text.trim(),
    };
    for (final entry in values.entries) {
      final result = await c.settings.save(AppSetting(key: entry.key, value: entry.value, updatedAt: c.clock.now()));
      if (result is Failure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message)));
        return;
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ قوالب سلفني')));
  }

  @override
  void dispose() {
    _accepted.dispose();
    _rejected.dispose();
    _settled.dispose();
    super.dispose();
  }

  Widget _field(String title, TextEditingController controller, String helper) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(controller: controller, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: title, helperText: helper, border: const OutlineInputBorder())),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: KayanColors.appBackground,
      appBar: AppBar(title: const Text('قوالب رسائل سلفني')),
      body: _loading ? const AsyncLoadingView() : ListView(padding: const EdgeInsets.all(16), children: [
        const Text('المتغيرات المتاحة: {amount} {serial} {code} {reason} {remaining}', style: TextStyle(fontFamily: 'Tajawal')),
        const SizedBox(height: 16),
        _field('رسالة القبول والتسليم', _accepted, 'تُرسل بعد إنشاء السلفة وتسليم الكرت'),
        _field('رسالة الرفض', _rejected, 'قالب أساس الإشعار عند رفض الطلب'),
        _field('رسالة السداد', _settled, 'تُستخدم عند تسديد السلفة كليًا أو جزئيًا'),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ القوالب')),
      ]),
    ),
  );
}
