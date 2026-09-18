import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/promotion.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_tab_header.dart';

/// إدارة العروض والمكافآت — مطابق فيديو Z Net (نشطة / معطّلة + عرض جديد).
///
/// المنطق كما هو (نفس الاستعلامات ونفس عمليات الإنشاء/التعديل/التفعيل/الحذف)،
/// والتحديث البصري فقط: هوية لونية موحّدة + أوراق وحالات موحّدة.
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
      setState(() {
        _loading = false;
        _error = listed.error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _items = (listed as Success<List<Promotion>>).value;
      _categoryNames = names;
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

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final thresholdCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (existing.thresholdMinorUnits / 100).toStringAsFixed(
              existing.thresholdMinorUnits % 100 == 0 ? 0 : 2,
            ),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var rewardId = categories.any((e) => e.id == existing?.rewardCategoryId)
        ? existing!.rewardCategoryId
        : categories.first.id;

    final saved = await NetSheet.show<bool>(
      context,
      builder: (ctx) {
        var busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return NetSheet(
              title: existing == null ? 'عرض ترويجي جديد' : 'تعديل العرض',
              subtitle: 'عند بلوغ العميل عتبة التراكم يُصرف كرت من فئة المكافأة.',
              icon: Icons.local_offer_rounded,
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NetSpacing.xl,
                  NetSpacing.lg,
                  NetSpacing.xl,
                  NetSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الحملة',
                        labelStyle: TextStyle(fontFamily: NetTypography.family),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: NetTypography.family),
                    ),
                    const SizedBox(height: NetSpacing.md),
                    TextField(
                      controller: thresholdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عتبة التراكم (ر.ي)',
                        hintText: 'مثال: 50000',
                        labelStyle: TextStyle(fontFamily: NetTypography.family),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: NetTypography.family),
                    ),
                    const SizedBox(height: NetSpacing.md),
                    DropdownButtonFormField<String>(
                      value: rewardId,
                      decoration: const InputDecoration(
                        labelText: 'فئة المكافأة',
                        labelStyle: TextStyle(fontFamily: NetTypography.family),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final cat in categories)
                          DropdownMenuItem(
                            value: cat.id,
                            child: Text(
                              '${cat.name} · ${formatMoneyMinor(cat.faceValue.minorUnits)}',
                              style: const TextStyle(fontFamily: NetTypography.family),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModal(() => rewardId = v);
                      },
                    ),
                    const SizedBox(height: NetSpacing.md),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        labelStyle: TextStyle(fontFamily: NetTypography.family),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: NetTypography.family),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: NetSpacing.md),
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: NetSizes.iconSm,
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                          const SizedBox(width: NetSpacing.sm),
                          Expanded(
                            child: Text(
                              status!,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              footer: FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setModal(() => busy = true);
                        final major = num.tryParse(
                          thresholdCtrl.text.trim().replaceAll(',', ''),
                        );
                        if (major == null || major <= 0) {
                          setModal(() {
                            busy = false;
                            status = 'أدخل عتبة صحيحة';
                          });
                          return;
                        }
                        final r = existing == null
                            ? await c.promotions.create(
                                title: titleCtrl.text,
                                thresholdMinorUnits: (major * 100).round(),
                                rewardCategoryId: rewardId,
                                notes: notesCtrl.text,
                              )
                            : await c.promotions.update(
                                id: existing.id,
                                title: titleCtrl.text,
                                thresholdMinorUnits: (major * 100).round(),
                                rewardCategoryId: rewardId,
                                notes: notesCtrl.text,
                              );
                        if (!ctx.mounted) return;
                        if (r is Success) {
                          Navigator.pop(ctx, true);
                        } else {
                          setModal(() {
                            busy = false;
                            status = (r as Failure).error.message;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('حفظ العرض'),
              ),
            );
          },
        );
      },
    );
    titleCtrl.dispose();
    thresholdCtrl.dispose();
    notesCtrl.dispose();
    if (saved == true) await _load();
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
          onEdit: () => _openForm(p),
          onToggle: () => _toggle(p),
          onDelete: () => _delete(p),
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
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final Promotion promotion;
  final String rewardName;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

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
                  if (v == 'toggle') onToggle();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('تعديل', style: TextStyle(fontFamily: NetTypography.family)),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      isActive ? 'تعطيل' : 'تفعيل',
                      style: const TextStyle(fontFamily: NetTypography.family),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'حذف',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        color: net.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: NetRadii.smAll,
            ),
            child: Row(
              children: [
                Icon(Icons.redeem_rounded, size: NetSizes.iconSm, color: palette.primary),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: Text(
                    'المكافأة: $rewardName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if ((promotion.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: NetSpacing.sm),
            Text(
              promotion.notes!.trim(),
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                height: 1.4,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
