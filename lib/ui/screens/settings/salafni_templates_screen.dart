import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/net_semantic_colors.dart';
import '../../widgets/async_views.dart';

/// تعديل صيغ رسائل خدمة «سلفني» (قبول / رفض / سداد) — قابلة للتخصيص بالكامل.
class SalafniTemplatesScreen extends StatefulWidget {
  const SalafniTemplatesScreen({super.key});

  @override
  State<SalafniTemplatesScreen> createState() => _SalafniTemplatesScreenState();
}

class _SalafniTemplatesScreenState extends State<SalafniTemplatesScreen> {
  bool _loading = true;
  bool _saving = false;
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
      if (r is Success<AppSetting?> && r.value?.value.trim().isNotEmpty == true) {
        return r.value!.value;
      }
      return fallback;
    }

    _accepted.text =
        await read(SettingKeys.salafniAcceptedTemplate, LocalAdvanceService.defaultAccepted);
    _rejected.text =
        await read(SettingKeys.salafniRejectedTemplate, LocalAdvanceService.defaultRejected);
    _settled.text =
        await read(SettingKeys.salafniSettledTemplate, LocalAdvanceService.defaultSettled);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = AppScope.of(context);
    final values = <String, String>{
      SettingKeys.salafniAcceptedTemplate: _accepted.text.trim(),
      SettingKeys.salafniRejectedTemplate: _rejected.text.trim(),
      SettingKeys.salafniSettledTemplate: _settled.text.trim(),
    };
    for (final entry in values.entries) {
      if (entry.value.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن ترك القالب فارغًا', style: TextStyle(fontFamily: 'Tajawal'))),
          );
        }
        setState(() => _saving = false);
        return;
      }
      final result = await c.settings.save(
        AppSetting(key: entry.key, value: entry.value, updatedAt: c.clock.now()),
      );
      if (result is Failure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
        );
        setState(() => _saving = false);
        return;
      }
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ قوالب سلفني', style: TextStyle(fontFamily: 'Tajawal'))),
      );
    }
  }

  Future<void> _resetDefaults() async {
    setState(() {
      _accepted.text = LocalAdvanceService.defaultAccepted;
      _rejected.text = LocalAdvanceService.defaultRejected;
      _settled.text = LocalAdvanceService.defaultSettled;
    });
  }

  @override
  void dispose() {
    _accepted.dispose();
    _rejected.dispose();
    _settled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'قوالب رسائل سلفني',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _loading ? null : _resetDefaults,
              child: const Text('الافتراضي', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري تحميل القوالب…')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.netColors.availableContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.netColors.available.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'عدّل نص الرسائل التي يرسلها النظام لخدمة سلفني.\n'
                      'المتغيرات: {amount} · {serial} · {code} · {reason} · {remaining}',
                      style: TextStyle(fontFamily: 'Tajawal', height: 1.45, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    title: 'رسالة القبول والتسليم',
                    hint: 'تُرسل بعد إنشاء السلفة وتسليم الكرت',
                    controller: _accepted,
                  ),
                  _field(
                    title: 'رسالة الرفض',
                    hint: 'عند رفض الطلب (رصيد/أهلية/خدمة متوقفة…)',
                    controller: _rejected,
                  ),
                  _field(
                    title: 'رسالة السداد',
                    hint: 'عند تسديد السلفة كليًا أو جزئيًا',
                    controller: _settled,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'جاري الحفظ…' : 'حفظ القوالب',
                      style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _field({
    required String title,
    required String hint,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'Tajawal', height: 1.4),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
