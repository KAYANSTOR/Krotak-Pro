import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/services/card_import_parser.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// المخزون / الفئات / الكروت / الاستيراد — B5–B7.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _available = const [];
  List<domain.Card> _reserved = const [];
  List<domain.Card> _sold = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
      _reserved =
          reserved is Success<List<domain.Card>> ? reserved.value : const [];
      _sold = sold is Success<List<domain.Card>> ? sold.value : const [];
    });
  }

  int _countFor(String categoryId, List<domain.Card> cards) =>
      cards.where((c) => c.categoryId == categoryId).length;

  List<domain.CardCategory> get _filtered {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return _categories;
    return _categories
        .where((c) =>
            c.name.contains(q) ||
            c.faceValue.minorUnits.toString().contains(q) ||
            formatMoneyMinor(c.faceValue.minorUnits).contains(q))
        .toList(growable: false);
  }

  Future<void> _createCategory() async {
    final nameCtrl = TextEditingController();
    final faceCtrl = TextEditingController(text: '1000');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'فئة جديدة',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'القيمة الاسمية تُستخدم لمطابقة مبلغ التحويل مع الفئة النشطة',
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الفئة',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: faceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'القيمة الاسمية (ر.ي)',
                  border: OutlineInputBorder(),
                  helperText: 'مثال: 1000 = ألف ريال يمني',
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              const SizedBox(height: 12),
              const Text(
                'العملة: YER (ثابتة في النسخة الحالية)',
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) {
      nameCtrl.dispose();
      faceCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    final faceMajor = int.tryParse(faceCtrl.text.trim()) ?? 0;
    nameCtrl.dispose();
    faceCtrl.dispose();
    if (name.isEmpty || faceMajor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اسم الفئة وقيمة موجبة مطلوبان',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    final c = AppScope.of(context);
    final r = await c.catalogService.saveCategory(
      domain.CardCategory(
        id: c.ids.next('cat'),
        name: name,
        faceValue: Money(minorUnits: faceMajor * 100, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (r as Failure).error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حفظ الفئة',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
    await _load();
  }

  Future<void> _openImport(domain.CardCategory category) async {
    if (!category.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكن إضافة كروت لفئة غير نشطة',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ImportCardsSheet(
        category: category,
        onDone: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Future<void> _openCategoryCards(domain.CardCategory category) async {
    final cards = [
      ..._available.where((c) => c.categoryId == category.id),
      ..._reserved.where((c) => c.categoryId == category.id),
      ..._sold.where((c) => c.categoryId == category.id),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'كروت · ${category.name}',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (category.isActive)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openImport(category);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'إضافة',
                            style: TextStyle(fontFamily: 'Tajawal'),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? const AsyncEmptyView(
                          message: 'لا كروت في هذه الفئة',
                          icon: Icons.credit_card_off,
                        )
                      : ListView.separated(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: cards.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final card = cards[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                card.serialNumber,
                                style: const TextStyle(fontFamily: 'Tajawal'),
                              ),
                              subtitle: Text(
                                _statusAr(card.status),
                                style: const TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Text(
                                card.secretCode.length > 4
                                    ? '••••${card.secretCode.substring(card.secretCode.length - 4)}'
                                    : '••••',
                                style: const TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _statusAr(domain.CardStatus s) {
    switch (s) {
      case domain.CardStatus.available:
        return 'متاح';
      case domain.CardStatus.reserved:
        return 'محجوز';
      case domain.CardStatus.sold:
        return 'مباع';
      case domain.CardStatus.disabled:
        return 'معطّل';
      case domain.CardStatus.expired:
        return 'منتهٍ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalAvail = _available.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'إدارة الفئات والكروت والمخزون',
            style: TextStyle(
              fontFamily: 'Tajawal',
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'بحث عن فئة',
                    hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _createCategory,
                icon: const Icon(Icons.add),
                tooltip: 'فئة جديدة',
              ),
            ],
          ),
        ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${_categories.length} فئة · $totalAvail كرت متاح · ${_reserved.length} محجوز · ${_sold.length} مباع',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const AsyncLoadingView()
              : _error != null
                  ? AsyncErrorView(message: _error!, onRetry: _load)
                  : _filtered.isEmpty
                      ? AsyncEmptyView(
                          message: _categories.isEmpty
                              ? 'لا فئات\nأنشئ فئة بقيمة اسمية قبل استيراد الكروت'
                              : 'لا نتائج للبحث',
                          icon: Icons.category_outlined,
                          actionLabel:
                              _categories.isEmpty ? 'فئة جديدة' : null,
                          onAction:
                              _categories.isEmpty ? _createCategory : null,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final cat = _filtered[i];
                              final avail = _countFor(cat.id, _available);
                              final reserved = _countFor(cat.id, _reserved);
                              final sold = _countFor(cat.id, _sold);
                              final total = avail + reserved + sold;
                              return _CategoryCard(
                                category: cat,
                                available: avail,
                                reserved: reserved,
                                sold: sold,
                                total: total,
                                onOpen: () => _openCategoryCards(cat),
                                onImport: () => _openImport(cat),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.available,
    required this.reserved,
    required this.sold,
    required this.total,
    required this.onOpen,
    required this.onImport,
  });

  final domain.CardCategory category;
  final int available;
  final int reserved;
  final int sold;
  final int total;
  final VoidCallback onOpen;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final isLow = available == 0;
    final tone = isLow
        ? (semantic?.rejected ?? cs.error)
        : (semantic?.success ?? Colors.green);

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.style_outlined, color: KayanColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.name,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (!category.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'غير نشطة',
                        style: TextStyle(fontFamily: 'Tajawal', fontSize: 11),
                      ),
                    ),
                  if (isLow && category.isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tone.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'منخفض',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'القيمة: ${formatMoneyMinor(category.faceValue.minorUnits)} ${category.faceValue.currencyCode}',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'متاح $available · محجوز $reserved · مباع $sold · الإجمالي $total',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpen,
                      child: const Text(
                        'عرض الكروت',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: category.isActive ? onImport : null,
                      child: const Text(
                        'استيراد / إضافة',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual + bulk paste import into an active category.
class _ImportCardsSheet extends StatefulWidget {
  const _ImportCardsSheet({
    required this.category,
    required this.onDone,
  });

  final domain.CardCategory category;
  final VoidCallback onDone;

  @override
  State<_ImportCardsSheet> createState() => _ImportCardsSheetState();
}

class _ImportCardsSheetState extends State<_ImportCardsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _serialCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _bulkCtrl = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _serialCtrl.dispose();
    _pinCtrl.dispose();
    _bulkCtrl.dispose();
    super.dispose();
  }

  Future<void> _importDrafts(List<CardImportDraft> drafts) async {
    if (drafts.isEmpty) {
      setState(() => _status = 'لا كروت للاستيراد');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final r = await c.catalogService.importCards(
      categoryId: widget.category.id,
      drafts: drafts,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure<int>) {
      setState(() => _status = r.error.message);
      return;
    }
    final n = (r as Success<int>).value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم استيراد $n كرت إلى ${widget.category.name}',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    widget.onDone();
  }

  Future<void> _submitSingle() async {
    final serial = _serialCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (serial.isEmpty || pin.isEmpty) {
      setState(() => _status = 'الرقم التسلسلي والرمز مطلوبان');
      return;
    }
    await _importDrafts([
      CardImportDraft(serialNumber: serial, secretCode: pin),
    ]);
  }

  Future<void> _submitBulk() async {
    final parsed = CardImportParser.parse(_bulkCtrl.text);
    if (parsed.hasErrors && !parsed.hasDrafts) {
      setState(() => _status = parsed.errors.take(5).join('\n'));
      return;
    }
    if (!parsed.hasDrafts) {
      setState(() => _status = 'لا أسطر صالحة');
      return;
    }
    if (parsed.hasErrors) {
      setState(() => _status =
          'سيتم استيراد ${parsed.drafts.length} وتجاوز أخطاء:\n${parsed.errors.take(3).join('\n')}');
    }
    await _importDrafts(parsed.drafts);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إضافة كروت · ${widget.category.name}',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Text(
            'القيمة ${formatMoneyMinor(widget.category.faceValue.minorUnits)} · لا يُسمح بلا فئة نشطة',
            style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            labelStyle: const TextStyle(fontFamily: 'Tajawal'),
            tabs: const [
              Tab(text: 'فردي'),
              Tab(text: 'جماعي / CSV'),
            ],
          ),
          SizedBox(
            height: 220,
            child: TabBarView(
              controller: _tabs,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _serialCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الرقم التسلسلي',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pinCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الرمز السري',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: _bulkCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'الصق الأسطر: serial,pin',
                      hintText:
                          'مثال:\n10001,ABCD\n10002;EFGH\n# تعليق يُتجاهل',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                color: KayanColors.warning,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    if (_tabs.index == 0) {
                      _submitSingle();
                    } else {
                      _submitBulk();
                    }
                  },
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'استيراد',
                    style: TextStyle(fontFamily: 'Tajawal'),
                  ),
          ),
        ],
      ),
    );
  }
}
