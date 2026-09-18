import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/default_outbound_templates_seeder.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

/// شاشة قوالب رسائل العملاء والعروض والنظام.
///
/// تعديل عرض فقط: نفس أقسام الكتالوج، ونفس مفاتيح الإعدادات، ونفس الزرع
/// التلقائي عند الإقلاع، ونفس سلوك «حفظ الكل» و«استعادة افتراضي القسم».
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
      icon: Icons.people_alt_rounded,
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
      icon: Icons.card_giftcard_rounded,
      isPremium: true,
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
      icon: Icons.volunteer_activism_rounded,
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
      icon: Icons.storefront_rounded,
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

  void _resetSection(_Section section) {
    for (final i in section.items) {
      _ctrls[i.keyName]!.text = i.fallback;
    }
    setState(() {});
  }

  void _resetItem(_Item item) {
    _ctrls[item.keyName]!.text = item.fallback;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          backgroundColor: palette.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'قوالب الرسائل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: palette.textPrimary,
                ),
              ),
              Text(
                'العملاء · العروض · سلفني · النظام',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: NetSpacing.sm),
              child: TextButton(
                onPressed: _loading ? null : _saveAll,
                child: Text(
                  'حفظ الكل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: palette.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  NetSpacing.lg,
                  NetSpacing.lg,
                  NetSpacing.lg,
                  NetSpacing.xxl + NetSpacing.lg,
                ),
                children: [
                  NetInlineNotice(
                    message:
                        'هذه القوالب تُزرع تلقائياً مع التطبيق. عدّل أي نص ثم «حفظ الكل»، أو استعد افتراضي القسم.',
                    icon: Icons.auto_awesome_rounded,
                    color: palette.primary,
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  for (final section in _sections) ...[
                    _SectionHeader(
                      section: section,
                      tint: section.isPremium
                          ? context.netColors.premium
                          : palette.primary,
                      onReset: () => _resetSection(section),
                    ),
                    const SizedBox(height: NetSpacing.sm),
                    for (final item in section.items)
                      _TemplateField(
                        item: item,
                        controller: _ctrls[item.keyName]!,
                        onReset: () => _resetItem(item),
                      ),
                    const SizedBox(height: NetSpacing.md),
                  ],
                ],
              ),
      ),
    );
  }
}

/// رأس القسم: شارة أيقونة ملوّنة + العنوان + «افتراضي».
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.tint,
    required this.onReset,
  });

  final _Section section;
  final Color tint;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Row(
      children: [
        Container(
          width: NetSizes.badge,
          height: NetSizes.badge,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: palette.isDark ? 0.22 : 0.10),
            borderRadius: NetRadii.smAll,
          ),
          child: Icon(section.icon, size: 20, color: tint),
        ),
        const SizedBox(width: NetSpacing.md),
        Expanded(
          child: Text(
            section.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: palette.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: onReset,
          child: Text(
            'افتراضي',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: palette.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// بطاقة قالب واحد: العنوان + شرائح المتغيّرات + حقل التعديل.
class _TemplateField extends StatelessWidget {
  const _TemplateField({
    required this.item,
    required this.controller,
    required this.onReset,
  });

  final _Item item;
  final TextEditingController controller;
  final VoidCallback onReset;

  /// يفصل نص المتغيّرات `{a} {b}` إلى شرائح مستقلة.
  static List<String> _variables(String hint) {
    return hint
        .split(RegExp(r'\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return NetSurfaceCard(
      margin: const EdgeInsets.only(bottom: NetSpacing.sm),
      padding: NetSpacing.cardTight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Tooltip(
                message: 'استعادة الافتراضي',
                child: InkWell(
                  onTap: onReset,
                  borderRadius: NetRadii.xsAll,
                  child: Padding(
                    padding: const EdgeInsets.all(NetSpacing.xs),
                    child: Icon(
                      Icons.restart_alt_rounded,
                      size: NetSizes.iconSm,
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Wrap(
            spacing: NetSpacing.xs + 2,
            runSpacing: NetSpacing.xs + 2,
            children: [
              for (final variable in _variables(item.hint))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.iconBadgeBackground,
                    borderRadius: NetRadii.pillAll,
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    variable,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              height: 1.5,
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: item.fallback,
              hintStyle: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textTertiary,
              ),
              filled: true,
              fillColor: palette.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: NetSpacing.md,
                vertical: NetSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: NetRadii.smAll,
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NetRadii.smAll,
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NetRadii.smAll,
                borderSide: BorderSide(color: palette.primary, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section({
    required this.title,
    required this.icon,
    required this.items,
    this.isPremium = false,
  });

  final String title;
  final IconData icon;
  final List<_Item> items;

  /// لمسة ذهبية محدودة على قسم العروض فقط.
  final bool isPremium;
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
