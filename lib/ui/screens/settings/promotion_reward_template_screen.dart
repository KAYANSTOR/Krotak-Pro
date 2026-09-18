import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/local_promotion_fulfillment_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../widgets/async_views.dart';

class PromotionRewardTemplateScreen extends StatefulWidget {
  const PromotionRewardTemplateScreen({super.key});

  @override
  State<PromotionRewardTemplateScreen> createState() =>
      _PromotionRewardTemplateScreenState();
}

class _PromotionRewardTemplateScreenState
    extends State<PromotionRewardTemplateScreen> {
  bool _loading = true;
  final _body = TextEditingController(
    text: LocalPromotionFulfillmentService.defaultRewardSmsTemplate,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final result = await c.settings.find(SettingKeys.promotionRewardSmsTemplate);
    final stored = result is Success<AppSetting?> ? result.value?.value : null;
    if (stored != null && stored.trim().isNotEmpty) {
      _body.text = stored;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardSmsTemplate,
        value: _body.text.trim(),
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ قالب مكافأة العرض')),
    );
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(title: const Text('قالب SMS لمكافأة العرض')),
          body: _loading
              ? const AsyncLoadingView()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'المتغيرات: {title} {serial} {secret} {code} {amount}',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _body,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'نص الرسالة',
                        helperText: 'تُرسل بعد صرف كرت المكافأة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ القالب'),
                    ),
                  ],
                ),
        ),
      );
}
