import 'package:flutter/material.dart';

import '../../../application/app_scope.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../../domain/services/default_outbound_templates_seeder.dart';
import '../../../core/result.dart';

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
      const SnackBar(
        content: Text(
          'تم حفظ جميع قوالب الرسائل',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'قوالب رسائل العملاء والعروض والنظام',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: _loading ? null : _saveAll,
              child: const Text('حفظ الكل', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                    'هذه القوالب تُزرع تلقائياً مع التطبيق (كما في الفيديو). '
                    'يمكنك تعديل أي نص ثم حفظ الكل، أو استعادة افتراضي القسم.',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final section in _sections) ...[
                    Row(
                      children: [
                        Icon(section.icon, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            section.title,
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _resetSection(section),
                          child: const Text(
                            'افتراضي',
                            style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final item in section.items)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'متغيرات: ${item.hint}',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _ctrls[item.keyName],
                                maxLines: 4,
                                style: const TextStyle(fontFamily: 'Tajawal'),
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintText: item.fallback,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
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
