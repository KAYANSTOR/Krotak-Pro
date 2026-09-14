import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/promotion.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

/// إدارة العروض والمكافآت — مطابق فيديو Z Net (نشطة / معطّلة + عرض جديد).
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

  Future<void> _create() async {
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
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String rewardId = categories.first.id;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'عرض ترويجي جديد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'عند بلوغ المشترك عتبة التراكم يُصرف كرت من فئة المكافأة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: 'عنوان الحملة',
                          labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: thresholdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'عتبة التراكم (ر.ي)',
                          hintText: 'مثال: 50000',
                          labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: rewardId,
                        decoration: InputDecoration(
                          labelText: 'فئة المكافأة',
                          labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          for (final cat in categories)
                            DropdownMenuItem(
                              value: cat.id,
                              child: Text(
                                '${cat.name} · ${formatMoneyMinor(cat.faceValue.minorUnits)} ر.ي',
                                style: const TextStyle(fontFamily: 'Tajawal'),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setModal(() => rewardId = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
                          labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          status!,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFA855F7),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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
                                final r = await c.promotions.create(
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
                            : const Text(
                                'حفظ العرض',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
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
            style: const TextStyle(fontFamily: 'Tajawal'),
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
        title: const Text('حذف العرض؟', style: TextStyle(fontFamily: 'Tajawal')),
        content: Text(
          'سيتم حذف «${p.title}» نهائيًا.',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal')),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_offer_outlined,
                  size: 36,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                active ? 'لا توجد عروض ترويجية' : 'لا عروض معطّلة',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? 'انقر على «عرض جديد» لتهيئة عرض ترويجي تراكمي جديد'
                    : 'العروض التي تعطّلها تظهر هنا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = items[i];
        final reward = _categoryNames[p.rewardCategoryId] ?? p.rewardCategoryId;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            title: Text(
              p.title,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'عتبة ${formatMoneyMinor(p.thresholdMinorUnits)} ر.ي · مكافأة: $reward',
              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'toggle') _toggle(p);
                if (v == 'delete') _delete(p);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    p.isActive ? 'تعطيل' : 'تفعيل',
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'حذف',
                    style: TextStyle(fontFamily: 'Tajawal', color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إدارة العروض والمكافآت',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'إدارة وتتبع حملات الترويج التراكمية',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: const Color(0xFF0F766E),
              unselectedLabelColor: const Color(0xFF94A3B8),
              indicatorColor: const Color(0xFF0F766E),
              labelStyle: const TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: 'النشطة'),
                Tab(text: 'المعطّلة'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            RefreshIndicator(
                              onRefresh: _load,
                              child: _list(true),
                            ),
                            RefreshIndicator(
                              onRefresh: _load,
                              child: _list(false),
                            ),
                          ],
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          backgroundColor: const Color(0xFFA855F7),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text(
            'عرض جديد',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
