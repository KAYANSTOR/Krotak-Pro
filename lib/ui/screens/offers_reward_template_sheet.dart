import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/local_promotion_fulfillment_service.dart';
import '../../domain/services/promotion_reward_template.dart';
import '../app_scope.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_surface_card.dart';

/// تحرير قالب رسالة المكافأة من شاشة العروض مع تتبّع الكتابة قبل الحفظ.
///
/// بدون [promotionId] يُحفظ القالب العام. مع معرّف العرض يُحفظ تخصيص هذا العرض فقط.
/// مع [customerId] يُحفظ تخصيص هذا العميل داخل العرض دون تغيير بقية العملاء.
Future<bool?> showOffersRewardTemplateSheet(
  BuildContext context, {
  String? promotionId,
  String? promotionTitle,
  String? customerId,
  String? customerLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OffersRewardTemplateSheet(
      promotionId: promotionId,
      promotionTitle: promotionTitle,
      customerId: customerId,
      customerLabel: customerLabel,
    ),
  );
}

class _OffersRewardTemplateSheet extends StatefulWidget {
  const _OffersRewardTemplateSheet({
    this.promotionId,
    this.promotionTitle,
    this.customerId,
    this.customerLabel,
  });

  final String? promotionId;
  final String? promotionTitle;
  final String? customerId;
  final String? customerLabel;

  @override
  State<_OffersRewardTemplateSheet> createState() =>
      _OffersRewardTemplateSheetState();
}

class _OffersRewardTemplateSheetState extends State<_OffersRewardTemplateSheet> {
  final _body = TextEditingController();
  var _loading = true;
  var _busy = false;
  var _dirty = false;
  String _draft = '';
  String? _status;

  String get _fallback =>
      LocalPromotionFulfillmentService.defaultRewardSmsTemplate;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTyped() {
    final next = _body.text;
    if (next == _draft && _dirty) return;
    setState(() {
      _draft = next;
      _dirty = true;
      _status = null;
    });
  }

  bool get _perOffer => widget.promotionId != null && widget.promotionId!.isNotEmpty;

  bool get _perCustomer =>
      _perOffer && widget.customerId != null && widget.customerId!.isNotEmpty;

  Future<void> _load() async {
    final c = AppScope.of(context);
    final global = await c.settings.find(SettingKeys.promotionRewardSmsTemplate);
    final stored = global is Success<AppSetting?> ? global.value?.value : null;
    var text = PromotionRewardTemplate.normalize(stored, fallback: _fallback);
    if (_perOffer) {
      final map = await c.settings.find(SettingKeys.promotionRewardSmsTemplates);
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      final specific = PromotionRewardTemplate.lookup(raw, widget.promotionId!);
      if (specific != null) text = specific;
    }
    if (_perCustomer) {
      final map = await c.settings.find(
        SettingKeys.promotionRewardCustomerSmsTemplates,
      );
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      final specific = PromotionRewardTemplate.lookupCustomer(
        raw,
        widget.promotionId!,
        widget.customerId!,
      );
      if (specific != null) text = specific;
    }
    _body.removeListener(_onTyped);
    _body.text = text;
    _body.addListener(_onTyped);
    if (!mounted) return;
    setState(() {
      _draft = text;
      _dirty = false;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final c = AppScope.of(context);
    late final AppSetting setting;
    if (_perCustomer) {
      final map = await c.settings.find(
        SettingKeys.promotionRewardCustomerSmsTemplates,
      );
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      setting = AppSetting(
        key: SettingKeys.promotionRewardCustomerSmsTemplates,
        value: PromotionRewardTemplate.encodeCustomerMap(
          raw,
          promotionId: widget.promotionId!,
          customerId: widget.customerId!,
          body: _draft.trim(),
        ),
        updatedAt: c.clock.now(),
      );
    } else if (_perOffer) {
      final map = await c.settings.find(SettingKeys.promotionRewardSmsTemplates);
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      setting = AppSetting(
        key: SettingKeys.promotionRewardSmsTemplates,
        value: PromotionRewardTemplate.encodeMap(
          raw,
          promotionId: widget.promotionId!,
          body: _draft.trim(),
        ),
        updatedAt: c.clock.now(),
      );
    } else {
      setting = AppSetting(
        key: SettingKeys.promotionRewardSmsTemplate,
        value: PromotionRewardTemplate.normalize(_draft, fallback: _fallback),
        updatedAt: c.clock.now(),
      );
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await c.settings.save(
      setting,
    );
    if (!mounted) return;
    if (result is Failure) {
      setState(() {
        _busy = false;
        _status = result.error.message;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _body.removeListener(_onTyped);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unknown = PromotionRewardTemplate.unknownPlaceholders(_draft);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: NetSpacing.screen,
          child: _loading
              ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _perCustomer
                          ? 'قالب العميل: ${widget.customerLabel ?? 'عميل العرض'}'
                          : _perOffer
                          ? 'قالب مكافأة: ${widget.promotionTitle ?? 'هذا العرض'}'
                          : 'قالب رسالة المكافأة',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _perOffer
                          ? 'يُستخدم لهذا العرض فقط. امسح النص واحفظ للعودة إلى القالب العام. المتغيرات: {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value}'
                          : 'القالب العام لكل العروض التي بلا قالب خاص. المتغيرات: {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value}',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    NetSurfaceCard(
                      child: TextField(
                        controller: _body,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'نص الرسالة',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: NetTypography.family),
                      ),
                    ),
                    if (unknown.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'متغيرات غير معروفة وستُرسل كما هي: ${unknown.map((e) => '{$e}').join(' ')}',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(_status!, style: TextStyle(fontFamily: NetTypography.family, color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy || !_dirty ? null : _save,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('حفظ القالب', style: TextStyle(fontFamily: NetTypography.family)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
