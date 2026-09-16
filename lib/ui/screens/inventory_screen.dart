import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/services/card_import_parser.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/reserved_card_ops.dart';

part 'inventory_widgets.dart';
part 'inventory_sheets.dart';

/// شاشة إدارة الكروت — مطابقة لتصميم فيديو Z Net + الصورة المرجعية.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

enum _StatusFilter { all, available, used }

class _InventoryScreenState extends State<InventoryScreen> {
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _allCards = const [];
  String? _categoryFilter;
  _StatusFilter _statusFilter = _StatusFilter.all;
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _chipColors = [
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final c = AppScope.of(context);
    final results = await Future.wait<dynamic>([
      c.categories.listAll(),
      c.cards.listByStatus(domain.CardStatus.available),
      c.cards.listByStatus(domain.CardStatus.reserved),
      c.cards.listByStatus(domain.CardStatus.sold),
      c.cards.listByStatus(domain.CardStatus.disabled),
      c.cards.listByStatus(domain.CardStatus.expired),
    ]);
    final cats = results[0];
    final avail = results[1];
    final reserved = results[2];
    final sold = results[3];
    final disabled = results[4];
    final expired = results[5];
    if (!mounted) return;

    final failures = <String>[];
    if (cats is Failure) failures.add('الفئات');
    if (avail is Failure) failures.add('المتوفرة');
    if (reserved is Failure) failures.add('المحجوزة');
    if (sold is Failure) failures.add('المباعة');
    if (disabled is Failure) failures.add('المعطلة');
    if (expired is Failure) failures.add('المنتهية');
    if (failures.isNotEmpty) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل: ${failures.join('، ')}';
      });
      return;
    }

    final list = <domain.Card>[
      ...(avail as Success<List<domain.Card>>).value,
      ...(reserved as Success<List<domain.Card>>).value,
      ...(sold as Success<List<domain.Card>>).value,
      ...(disabled as Success<List<domain.Card>>).value,
      ...(expired as Success<List<domain.Card>>).value,
    ];
    setState(() {
      _loading = false;
      _categories = (cats as Success<List<domain.CardCategory>>).value
          .where((e) => e.isActive)
          .toList();
      _allCards = list;
    });
  }

  domain.CardCategory? _catOf(domain.Card card) {
    for (final c in _categories) {
      if (c.id == card.categoryId) return c;
    }
    return null;
  }

  List<domain.Card> get _filtered {
    var list = _allCards;
    if (_categoryFilter != null) {
      list = list.where((c) => c.categoryId == _categoryFilter).toList();
    }
    switch (_statusFilter) {
      case _StatusFilter.available:
        list = list
            .where((c) =>
                c.status == domain.CardStatus.available ||
                c.status == domain.CardStatus.reserved)
            .toList();
      case _StatusFilter.used:
        list = list
            .where((c) =>
                c.status == domain.CardStatus.sold ||
                c.status == domain.CardStatus.disabled ||
                c.status == domain.CardStatus.expired)
            .toList();
      case _StatusFilter.all:
        break;
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((c) =>
              c.serialNumber.toLowerCase().contains(q) ||
              c.secretCode.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  String _fmtFace(Money m) {
    final major = m.minorUnits / 100.0;
    final s = major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ر.ي';
  }

  String _fmtFaceShort(Money m) {
    final major = m.minorUnits / 100.0;
    return major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
  }

  Future<void> _openCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CategoriesSheet(
        categories: _categories,
        onChanged: _load,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openAddCards() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أنشئ فئة كروت أولاً', style: TextStyle(fontFamily: 'Tajawal')),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddCardsSheet(
        categories: _categories,
        initialCategoryId: _categoryFilter ?? _categories.first.id,
        onDone: _load,
      ),
    );
    if (mounted) await _load();
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: KayanColors.appBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('إدارة الفئات', style: TextStyle(fontFamily: 'Tajawal')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openCategories();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('الكروت المتاحة للبيع', style: TextStyle(fontFamily: 'Tajawal')),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _statusFilter = _StatusFilter.available);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: const Text('الكروت المستخدمة والمنتهية', style: TextStyle(fontFamily: 'Tajawal')),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _statusFilter = _StatusFilter.used);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUsedCards() {
    setState(() => _statusFilter = _StatusFilter.used);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم فتح الكروت المستخدمة والمنتهية', style: TextStyle(fontFamily: 'Tajawal')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: KayanColors.appBackground,
        child: Column(
          children: [
            _Header(
              onMenu: _openMenu,
              onAdd: _openAddCards,
              onDelete: _showUsedCards,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _TopActionButton(
                      label: 'الفئات',
                      icon: Icons.category_outlined,
                      onTap: _openCategories,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TopActionButton(
                      label: 'إضافة الكروت',
                      icon: Icons.cloud_upload_outlined,
                      onTap: _openAddCards,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontFamily: 'Tajawal'),
                decoration: InputDecoration(
                  hintText: 'البحث برقم الكرت...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: KayanColors.textTertiary,
                  ),
                  prefixIcon: const Icon(Icons.search, color: KayanColors.textTertiary),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _CategoryChip(
                    label: 'الكل',
                    selected: _categoryFilter == null,
                    onTap: () => setState(() => _categoryFilter = null),
                  ),
                  ...List.generate(_categories.length, (i) {
                    final cat = _categories[i];
                    final color = _chipColors[i % _chipColors.length];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryChip(
                        label: 'كرت ${_fmtFaceShort(cat.faceValue)}',
                        selected: _categoryFilter == cat.id,
                        dotColor: color,
                        onTap: () => setState(() => _categoryFilter = cat.id),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusChip(
                    label: 'الكل',
                    selected: _statusFilter == _StatusFilter.all,
                    onTap: () => setState(() => _statusFilter = _StatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'كروت متوفرة',
                    selected: _statusFilter == _StatusFilter.available,
                    onTap: () => setState(() => _statusFilter = _StatusFilter.available),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'كروت مستخدمة',
                    selected: _statusFilter == _StatusFilter.used,
                    onTap: () => setState(() => _statusFilter = _StatusFilter.used),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: KayanColors.primary,
                          child: _filtered.isEmpty
                              ? ListView(
                                  children: const [
                                    SizedBox(height: 80),
                                    Center(
                                      child: Text(
                                        'لا توجد كروت مطابقة',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          color: KayanColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: _filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final card = _filtered[i];
                                    final cat = _catOf(card);
                                    return _TicketCard(
                                      card: card,
                                      faceLabel: cat != null ? _fmtFace(cat.faceValue) : '—',
                                      onTap: () {
                                        if (card.status == domain.CardStatus.reserved &&
                                            cat != null) {
                                          showReservedCardOps(
                                            context: context,
                                            card: card,
                                            category: cat,
                                            onDone: _load,
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
