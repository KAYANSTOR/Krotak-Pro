import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/promotion.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/promotion_reward_template.dart';
import '../app_scope.dart';
import '../perf/screen_open_trace.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_tab_header.dart';
import 'offers_reward_template_sheet.dart';
import 'offers_wizard_sheet.dart';

/// إدارة العروض والمكافآت — مطابق فيديو Z Net (نشطة / معطّلة + عرض جديد).
///
/// المنطق كما هو (نفس الاستعلامات ونفس عمليات الإنشاء/التعديل/التفعيل/الحذف).
/// إنشاء/تعديل العرض عبر معالج 4 خطوات مطابق الفيديو.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Promotion> _items = const [];
  Map<String, String> _categoryNames = const {};
  Set<String> _customTemplateIds = const {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final listed = await c.promotions.listAll();
    final cats = await c.categories.listAll();
    if (!mounted) return;
    final names = <String, String>{};
    if (cats is Success<List<CardCategory>>) {
      for (final cat in cats.value) {
        names[cat.id] = cat.name;
      }
    }
    if (listed is Failure<List<Promotion>>) {
      ScreenOpenTrace.instance.markLatestDataReady('offers');
      setState(() {
        _loading = false;
        _error = listed.error.message;
      });
      return;
    }
    final templates = await c.settings.find(SettingKeys.promotionRewardSmsTemplates);
    final raw = templates is Success<AppSetting?> ? templates.value?.value : null;
    if (!mounted) return;
    ScreenOpenTrace.instance.markLatestDataReady('offers');
    setState(() {
      _loading = false;
      _items = (listed as Success<List<Promotion>>).value;
      _categoryNames = names;
      _customTemplateIds = PromotionRewardTemplate.decodeMap(raw).keys.toSet();
    });
  }

  List<Promotion> _filtered(bool active) =>
      _items.where((p) => p.isActive == active).toList(growable: false);

  Future<void> _create() => _openForm();

  Future<void> _openForm([Promotion? existing]) async {
    final c = AppScope.of(context);
    final catsResult = await c.categories.listAll();
    if (!mounted) return;
    final categories = catsResult is Success<List<CardCategory>>
        ? catsResult.value.where((e) => e.isActive).toList()
        : const <CardCategory>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'أنشئ فئة كروت نشطة أولًا قبل تعريف عرض',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
        ),
      );
      return;
    }

    final saved = await showOffersWizardSheet(
      context: context,
      categories: categories,
      existing: existing,
    );
    if (saved == true) await _load();
  }

  Future<void> _editTemplate(Promotion p) async {
    final saved = await showOffersRewardTemplateSheet(
      context,
      promotionId: p.id,
      promotionTitle: p.title,
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ قالب مكافأة «${p.title}»')),
    );
    await _load();
  }

  Future<void> _editCustomerTemplate(Promotion p) async {
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CustomerTemplatePhoneDialog(),
    );
    if (!mounted || phone == null || phone.trim().isEmpty) return;
    final found = await AppScope.of(context).customers.search(phone.trim());
    if (!mounted) return;
    if (found is Failure<List<Customer>>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(found.error.message)),
      );
      return;
    }
    final matches = (found as Success<List<Customer>>).value;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد عميل بهذا الرقم')),
      );
      return;
    }
    final customer = matches.length == 1
        ? matches.first
        : await showDialog<Customer>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('اختر العميل'),
              children: [
                for (final item in matches)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, item),
                    child: Text(item.displayName),
                  ),
              ],
            ),
          );
    if (!mounted || customer == null) return;
    final saved = await showOffersRewardTemplateSheet(
      context,
      promotionId: p.id,
      promotionTitle: p.title,
      customerId: customer.id,
      customerLabel: customer.displayName,
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حفظ قالب «${customer.displayName}» في «${p.title}»'),
      ),
    );
  }

  Future<void> _toggle(Promotion p) async {
    final next = p.isActive ? PromotionStatus.disabled : PromotionStatus.active;
    final r = await AppScope.of(context).promotions.setStatus(p.id, next);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.message,
            style: const TextStyle(fontFamily: NetTypography.family),
          ),
        ),
      );
    }
    await _load();
  }

  Future<void> _delete(Promotion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العرض؟'),
        content: Text('سيتم حذف «${p.title}» نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppScope.of(context).promotions.delete(p.id);
    await _load();
  }

  Widget _list(bool active) {
    final items = _filtered(active);
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: NetSpacing.listBottomInset,
        children: [
          const SizedBox(height: NetSpacing.xxl),
          AsyncEmptyView(
            message: active ? 'لا توجد عروض ترويجية' : 'لا عروض معطّلة',
            icon: active ? Icons.local_offer_outlined : Icons.pause_circle_outline_rounded,
            hint: active
                ? 'أنشئ عرضًا تراكميًا وحدّد عتبة التراكم وفئة المكافأة'
                : 'العروض التي تعطّلها تظهر هنا',
            actionLabel: active ? 'عرض جديد' : null,
            onAction: active ? _create : null,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: NetSpacing.sm),
      itemBuilder: (_, i) {
        final p = items[i];
        final reward = _categoryNames[p.rewardCategoryId] ?? p.rewardCategoryId;
        return _PromotionCard(
          promotion: p,
          rewardName: reward,
          hasCustomTemplate: _customTemplateIds.contains(p.id),
          onEdit: () => _openForm(p),
          onToggle: () => _toggle(p),
          onDelete: () => _delete(p),
          onTemplate: () => _editTemplate(p),
          onCustomerTemplate: () => _editCustomerTemplate(p),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetTabHeader(
          title: 'العروض والمكافآت',
          subtitle: 'إدارة وتتبع حملات الترويج التراكمية',
          icon: Icons.local_offer_rounded,
          actions: [
            NetHeaderAction(
              icon: Icons.sms_outlined,
              tooltip: 'قالب رسالة المكافأة',
              onPressed: () async {
                final saved = await showOffersRewardTemplateSheet(context);
                if (!mounted || saved != true) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حفظ قالب مكافأة العرض')),
                );
              },
            ),
            NetHeaderAction(
              icon: Icons.add_rounded,
              tooltip: 'عرض جديد',
              onPressed: _create,
            ),
          ],
        ),
        Padding(
          padding: NetSpacing.pageH,
          child: TabBar(
            controller: _tabs,
            labelColor: palette.primary,
            unselectedLabelColor: palette.textSecondary,
            indicatorColor: palette.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: palette.border,
            labelStyle: const TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            tabs: [
              Tab(text: 'النشطة (${_filtered(true).length})'),
              Tab(text: 'المعطّلة (${_filtered(false).length})'),
            ],
          ),
        ),
        const SizedBox(height: NetSpacing.sm),
        Expanded(
          child: _loading
              ? const AsyncLoadingView(skeleton: true, skeletonCount: 4)
              : _error != null
                  ? AsyncErrorView(message: _error!, onRetry: _load)
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          color: palette.primary,
                          child: _list(true),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          color: palette.primary,
                          child: _list(false),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.rewardName,
    required this.hasCustomTemplate,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onTemplate,
    required this.onCustomerTemplate,
  });

  final Promotion promotion;
  final String rewardName;
  final bool hasCustomTemplate;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTemplate;
  final VoidCallback onCustomerTemplate;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final isActive = promotion.isActive;
    final statusBg = isActive ? net.successContainer : palette.surfaceVariant;

    return NetSurfaceCard(
      margin: NetSpacing.pageH,
      padding: NetSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: NetSizes.badge,
                height: NetSizes.badge,
                decoration: BoxDecoration(
                  color: net.premiumContainer,
                  borderRadius: NetRadii.smAll,
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  size: 20,
                  color: net.premium,
                ),
              ),
              const SizedBox(width: NetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promotion.title.isEmpty ? 'عرض بدون عنوان' : promotion.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: NetSpacing.xxs),
                    Text(
                      'عتبة ${formatMoneyMinor(promotion.thresholdMinorUnits)}',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.sm,
                  vertical: NetSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: NetRadii.pillAll,
                ),
                child: Text(
                  isActive ? 'نشط' : 'معطّل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isActive ? net.success : palette.textSecondary,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات العرض',
                icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'template') onTemplate();
                  if (v == 'customer_template') onCustomerTemplate();
                  if (v == 'toggle') onToggle();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  const PopupMenuItem(value: 'template', child: Text('قالب المكافأة')),
                  const PopupMenuItem(
                    value: 'customer_template',
                    child: Text('قالب لعميل'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(isActive ? 'تعطيل' : 'تفعيل'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Text(
            hasCustomTemplate ? 'مكافأة: $rewardName · قالب خاص' : 'مكافأة: $rewardName',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12.5,
              color: palette.textSecondary,
            ),
          ),
          if (promotion.notes != null && promotion.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: NetSpacing.xs),
            Text(
              promotion.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerTemplatePhoneDialog extends StatefulWidget {
  const _CustomerTemplatePhoneDialog();

  @override
  State<_CustomerTemplatePhoneDialog> createState() =>
      _CustomerTemplatePhoneDialogState();
}

class _CustomerTemplatePhoneDialogState
    extends State<_CustomerTemplatePhoneDialog> {
  final _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('قالب مكافأة لعميل'),
      content: TextField(
        controller: _phone,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'رقم الجوال أو الاسم',
          hintText: 'يُحفظ لهذا العميل داخل العرض فقط',
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _phone.text.trim()),
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}

