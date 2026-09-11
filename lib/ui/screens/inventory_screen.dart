import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _available = const [];
  List<domain.Card> _reserved = const [];
  List<domain.Card> _sold = const [];

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
    final cats = await c.categories.listAll();
    final avail = await c.cards.listByStatus(domain.CardStatus.available);
    final reserved = await c.cards.listByStatus(domain.CardStatus.reserved);
    final sold = await c.cards.listByStatus(domain.CardStatus.sold);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (cats is Failure) {
        _error = (cats as Failure).error.message;
        return;
      }
      _categories = (cats as Success<List<domain.CardCategory>>).value;
      _available = avail is Success<List<domain.Card>> ? avail.value : const [];
      _reserved = reserved is Success<List<domain.Card>> ? reserved.value : const [];
      _sold = sold is Success<List<domain.Card>> ? sold.value : const [];
    });
  }

  Future<void> _createCategory() async {
    final nameCtrl = TextEditingController();
    final faceCtrl = TextEditingController(text: '1000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فئة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم الفئة'),
            ),
            TextField(
              controller: faceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'القيمة الاسمية (ر.ي)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      nameCtrl.dispose();
      faceCtrl.dispose();
      return;
    }
    final c = AppScope.of(context);
    final face = int.tryParse(faceCtrl.text.trim()) ?? 0;
    final r = await c.catalogService.saveCategory(
      domain.CardCategory(
        id: c.ids.next('cat'),
        name: nameCtrl.text.trim(),
        faceValue: Money(minorUnits: face * 100, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    nameCtrl.dispose();
    faceCtrl.dispose();
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
    }
    await _load();
  }

  Future<void> _importCards(domain.CardCategory category) async {
    final serialCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('استيراد إلى ${category.name}', style: const TextStyle(fontFamily: 'Tajawal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'الرقم التسلسلي')),
            TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: 'الرمز السري')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استيراد')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      serialCtrl.dispose();
      pinCtrl.dispose();
      return;
    }
    final c = AppScope.of(context);
    final r = await c.catalogService.importCards(
      categoryId: category.id,
      drafts: [
        CardImportDraft(
          serialNumber: serialCtrl.text.trim(),
          secretCode: pinCtrl.text.trim(),
        ),
      ],
    );
    serialCtrl.dispose();
    pinCtrl.dispose();
    if (!mounted) return;
    final msg = r is Success<int>
        ? 'تم استيراد ${r.value} كرت'
        : (r as Failure).error.message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  Future<void> _reserve(domain.CardCategory category) async {
    final c = AppScope.of(context);
    final now = c.clock.now();
    final r = await c.inventoryService.reserveAvailableCard(
      categoryId: category.id,
      reservationId: c.ids.next('res'),
      now: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    if (!mounted) return;
    final msg = r is Success<domain.Card>
        ? 'تم حجز ${r.value.serialNumber}'
        : (r as Failure).error.message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AsyncLoadingView();
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'الفئات'),
            Tab(text: 'المخزون'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // Categories
              _categories.isEmpty
                  ? AsyncEmptyView(
                      message: 'لا توجد فئات',
                      actionLabel: 'إضافة فئة',
                      onAction: _createCategory,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _categories.length,
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          return ListTile(
                            title: Text(
                              cat.name,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              formatMoneyMinor(cat.faceValue.minorUnits),
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'import') _importCards(cat);
                                if (v == 'reserve') _reserve(cat);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'import', child: Text('استيراد كرت')),
                                PopupMenuItem(value: 'reserve', child: Text('حجز كرت')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
              // Stock
              RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  children: [
                    _stockSection('متاح', _available),
                    _stockSection('محجوز', _reserved),
                    _stockSection('مباع', _sold),
                    if (_available.isEmpty && _reserved.isEmpty && _sold.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: AsyncEmptyView(message: 'المخزون فارغ'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _createCategory,
            icon: const Icon(Icons.add),
            label: const Text('فئة جديدة'),
          ),
        ),
      ],
    );
  }

  Widget _stockSection(String title, List<domain.Card> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$title (${cards.length})',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.bold,
              color: KayanColors.primary,
            ),
          ),
        ),
        ...cards.map(
          (card) => ListTile(
            dense: true,
            title: Text(card.serialNumber, style: const TextStyle(fontFamily: 'Tajawal')),
            subtitle: Text(card.categoryId, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11)),
            trailing: Text(card.status.name, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
