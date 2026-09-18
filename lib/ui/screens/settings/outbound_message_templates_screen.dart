import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/default_outbound_templates_seeder.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

/// شاشة قوالب رسائل العملاء والعروض والنظام — مطابقة كتالوج الفيديو.
///
/// كل قالب يُزرع تلقائياً عند الإقلاع ويمكن تعديله وحفظه أو استعادة الافتراضي.
class OutboundMessageTemplatesScreen extends StatefulWidget {
  const OutboundMessageTemplatesScreen({super.key});

  @override
  State<OutboundMessageTemplatesScreen> createState() =>
      _OutboundMessageTemplatesScreenState();
}

class _OutboundMessageTemplatesScreenState
    extends State<OutboundMessageTemplatesScreen> {
  bool _loading = true;
  final Map<String, TextEditingController> _ctrls = {};

  static const _sections = <_Section>[
    _Section(
      title: 'رسائل العملاء',
      icon: Icons.people_outline,
      items: [
        _Item(
          keyName: SettingKeys.voucherDeliverySmsTemplate,
          title: 'تسليم الكرت للعميل',
          hint: '{serial} {code}',
          fallback: SettingDefaults.voucherDeliverySmsTemplate,
        ),
        _Item(
          keyName: SettingKeys.customerDebtPaymentTemplate,
          title: 'تأكيد سداد دين العميل',
          hint: '{amount} {balance}',
          fallback: SettingDefaults.customerDebtPaymentTemplate,
        ),
      ],
    ),
    _Section(
      title: 'العروض',
      icon: Icons.local_offer_outlined,
      items: [
        _Item(
          keyName: SettingKeys.promotionRewardSmsTemplate,
          title: 'مكافأة العرض',
          hint: '{title} {serial} {secret}',
          fallback: SettingDefaults.promotionRewardSmsTemplate,
        ),
      ],
    ),
    _Section(
      title: 'سلفني',
      icon: Icons.volunteer_activism_outlined,
      items: [
        _Item(
          keyName: SettingKeys.salafniAcceptedTemplate,
          title: 'قبول سلفني',
          hint: '{amount} {serial} {code}',
          fallback: LocalAdvanceService.defaultAccepted,
        ),
        _Item(
          keyName: SettingKeys.salafniRejectedTemplate,
          title: 'رفض سلفني',
          hint: '{reason}',
          fallback: LocalAdvanceService.defaultRejected,
        ),
        _Item(
          keyName: SettingKeys.salafniSettledTemplate,
          title: 'سداد سلفني',
          hint: '{amount} {remaining}',
          fallback: LocalAdvanceService.defaultSettled,
        ),
      ],
    ),
    _Section(
      title: 'النظام ونقاط البيع',
      icon: Icons.storefront_outlined,
      items: [
        _Item(
          keyName: SettingKeys.posBalanceResponseTemplate,
          title: 'رد استعلام رصيد النقطة',
          hint: '{pos} {balance} {debt}',
          fallback: SettingDefaults.posBalanceResponseTemplate,
        ),
        _Item(
          keyName: SettingKeys.posCreditLimitExceededTemplate,
          title: 'تجاوز سقف الدين',
          hint: '{pos} {limit}',
          fallback: SettingDefaults.posCreditLimitExceededTemplate,
        ),
        _Item(
          keyName: SettingKeys.dailyPosSummaryTemplate,
          title: 'الملخص اليومي لنقطة البيع',
          hint: '{pos} {sales} {transfers} {balance}',
          fallback: SettingDefaults.dailyPosSummaryTemplate,
        ),
        _Item(
          keyName: SettingKeys.posSettlementSuccessTemplate,
          title: 'تأكيد تسوية ناجحة',
          hint: '{pos} {amount}',
          fallback: SettingDefaults.posSettlementSuccessTemplate,
        ),
        _Item(
          keyName: SettingKeys.posSettlementFailedTemplate,
          title: 'فشل التسوية',
          hint: '{pos} {reason}',
          fallback: SettingDefaults.posSettlementFailedTemplate,
        ),
        _Item(
          keyName: SettingKeys.posSettlementUnknownTemplate,
          title: 'تسوية غير مؤكدة',
          hint: '{pos}',
          fallback: SettingDefaults.posSettlementUnknownTemplate,
        ),
        _Item(
          keyName: SettingKeys.posRequestRejectedTemplate,
          title: 'رفض طلب نقطة البيع',
          hint: '{pos} {reason}',
          fallback: SettingDefaults.posRequestRejectedTemplate,
        ),
        _Item(
          keyName: SettingKeys.posCustomerSmsTailTemplate,
          title: 'ذيل رسالة باسم نقطة البيع',
          hint: '{pos}',
          fallback: SettingDefaults.posCustomerSmsTailTemplate,
        ),
        _Item(
          keyName: SettingKeys.lowStockAlertTemplate,
          title: 'تنبيه انخفاض المخزون',
          hint: '{category} {count}',
          fallback: SettingDefaults.lowStockAlertTemplate,
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    for (final s in _sections) {
      for (final i in s.items) {
        _ctrls[i.keyName] = TextEditingController();
      }
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    await DefaultOutboundTemplatesSeeder(
      settings: c.settings,
      clock: c.clock,
    ).seedIfNeeded();

    for (final s in _sections) {
      for (final i in s.items) {
        final r = await c.settings.find(i.keyName);
        final raw = r is Success<AppSetting?> ? r.value?.value : null;
        _ctrls[i.keyName]!.text =
            (raw != null && raw.trim().isNotEmpty) ? raw : i.fallback;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    final c = AppScope.of(context);
    final now = c.clock.now();
    for (final e in _ctrls.entries) {
      final body = e.value.text.trim();
      if (body.isEmpty) continue;
      await c.settings.save(AppSetting(key: e.key, value: body, updatedAt: now));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ جميع قوالب الرسائل')),
    );
  }

  Future<void> _resetSection(_Section section) async {
    for (final i in section.items) {
      _ctrls[i.keyName]!.text = i.fallback;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'قوالب رسائل العملاء والعروض والنظام',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: _loading ? null : _saveAll,
              child: const Text('حفظ الكل'),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
            : ListView(
                padding: NetSpacing.screen,
                children: [
                  const NetInlineNotice(
                    message:
                        'هذه القوالب تُزرع تلقائياً مع التطبيق. يمكنك تعديل أي نص ثم حفظ الكل، أو استعادة افتراضي القسم.',
                    icon: Icons.info_outline_rounded,
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  for (final section in _sections) ...[
                    Row(
                      children: [
                        Icon(section.icon, size: 20, color: palette.primary),
                        const SizedBox(width: NetSpacing.sm),
                        Expanded(
                          child: Text(
                            section.title,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _resetSection(section),
                          child: const Text('افتراضي'),
                        ),
                      ],
                    ),
                    const SizedBox(height: NetSpacing.sm),
                    for (final item in section.items)
                      NetSurfaceCard(
                        margin: const EdgeInsets.only(bottom: NetSpacing.sm),
                        padding: NetSpacing.cardTight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: NetSpacing.xxs),
                            Text(
                              'متغيرات: ${item.hint}',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 11,
                                color: palette.textTertiary,
                              ),
                            ),
                            const SizedBox(height: NetSpacing.sm),
                            TextField(
                              controller: _ctrls[item.keyName],
                              maxLines: 4,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: item.fallback,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: NetSpacing.md),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Section {
  const _Section({
    required this.title,
    required this.icon,
    required this.items,
  });
  final String title;
  final IconData icon;
  final List<_Item> items;
}

class _Item {
  const _Item({
    required this.keyName,
    required this.title,
    required this.hint,
    required this.fallback,
  });
  final String keyName;
  final String title;
  final String hint;
  final String fallback;
}
