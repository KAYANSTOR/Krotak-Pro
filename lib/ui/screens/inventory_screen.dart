import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/services/card_import_parser.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../labels/net_labels.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_sparkline.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_tab_header.dart';
import 'inventory_categories_sheet.dart';

part 'inventory_sheets.dart';

/// شاشة إدارة الكروت — مطابقة لتصميم فيديو Z Net + الصورة المرجعية.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _cards = const [];
  String _query = '';
  String? _categoryFilter;
  domain.CardStatus? _statusFilter;
  bool _revealSecrets = false;
  final _searchCtrl = TextEditingController();

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
    final cards = await c.cards.listAll();
    if (!mounted) return;
    if (cats is Failure || cards is Failure) {
      setState(() {
        _loading = false;
        _error = cats is Failure
            ? (cats as Failure<dynamic>).error.message
            : (cards as Failure<dynamic>).error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _categories = (cats as Success<List<domain.CardCategory>>).value;
      _cards = (cards as Success<List<domain.Card>>).value;
    });
  }

  int _countFor(domain.CardStatus status, {String? categoryId}) {
    var n = 0;
    for (final card in _cards) {
      if (card.status != status) continue;
      if (categoryId != null && card.categoryId != categoryId) continue;
      n++;
    }
    return n;
  }

  List<domain.Card> get _filtered {
    final q = _query.trim().toLowerCase();
    return _cards.where((card) {
      if (_categoryFilter != null && card.categoryId != _categoryFilter) return false;
      if (_statusFilter != null && card.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      final catName = _categories.where((c) => c.id == card.categoryId).map((c) => c.name).firstOrNull ?? '';
      return card.serial.toLowerCase().contains(q) ||
          (card.secret ?? '').toLowerCase().contains(q) ||
          catName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openAddCards() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنشئ فئة أولاً قبل إضافة الكروت', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await NetSheet.show<void>(
      context,
      builder: (ctx) => _AddCardsSheet(
        categories: _categories,
        initialCategoryId: _categoryFilter ?? _categories.first.id,
        onDone: _load,
      ),
    );
  }

  Future<void> _openCategories() async {
    await showCategoriesSheet(
      context: context,
      categories: _categories,
      cards: _cards,
      onChanged: _load,
    );
  }

  void _resetInventoryFilters() {
    setState(() {
      _query = '';
      _categoryFilter = null;
      _statusFilter = null;
      _searchCtrl.clear();
    });
  }

  Future<void> _openOverflowMenu() async {
    await NetSheet.show<void>(
      context,
      builder: (ctx) => NetSheet(
        title: 'خيارات الكروت',
        icon: Icons.tune_rounded,
        children: [
          ListTile(
            leading: Icon(Icons.category_rounded, color: KayanPalette.of(ctx).primary),
            title: const Text('إدارة الفئات'),
            subtitle: Text(_categories.length.toString() + ' فئة'),
            onTap: () {
              Navigator.pop(ctx);
              _openCategories();
            },
          ),
          ListTile(
            leading: Icon(Icons.cloud_upload_rounded, color: KayanPalette.of(ctx).primary),
            title: const Text('استيراد كروت'),
            subtitle: const Text('لصق يدوي أو ملف نصي/CSV'),
            onTap: () {
              Navigator.pop(ctx);
              _openAddCards();
            },
          ),
          ListTile(
            leading: Icon(Icons.filter_alt_off_rounded, color: KayanPalette.of(ctx).primary),
            title: const Text('إعادة ضبط الفلاتر'),
            onTap: () {
              Navigator.pop(ctx);
              _resetInventoryFilters();
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.visibility_rounded, color: KayanPalette.of(ctx).primary),
            title: const Text('إظهار الأسرار'),
            value: _revealSecrets,
            onChanged: (v) {
              setState(() => _revealSecrets = v);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AsyncLoadingView(skeleton: true, skeletonCount: 6);
    }
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }

    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final available = _countFor(domain.CardStatus.available);
    final reserved = _countFor(domain.CardStatus.reserved);
    final sold = _countFor(domain.CardStatus.sold);
    final total = available + reserved + sold;
    final ratio = total == 0 ? 0.0 : available / total;

    return RefreshIndicator(
      onRefresh: _load,
      color: palette.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: NetSpacing.listBottomInset,
        children: [
          NetTabHeader(
            title: 'إدارة الكروت',
            subtitle: 'المخزون · الفئات · الاستيراد',
            icon: Icons.inventory_2_rounded,
            actions: [
              NetHeaderAction(
                icon: Icons.category_rounded,
                tooltip: 'الفئات',
                onPressed: _openCategories,
              ),
              NetHeaderAction(
                icon: Icons.add_rounded,
                tooltip: 'إضافة',
                onPressed: _openAddCards,
              ),
              NetHeaderAction(
                icon: Icons.more_vert_rounded,
                tooltip: 'المزيد',
                onPressed: _openOverflowMenu,
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          NetSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'المخزون الكلي',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '$available متوفر',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w700,
                        color: net.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NetSpacing.sm),
                ClipRRect(
                  borderRadius: NetRadii.pillAll,
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: palette.surfaceVariant,
                    color: ratio < 0.15 ? net.rejected : palette.primary,
                  ),
                ),
                const SizedBox(height: NetSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StatChip(label: 'متوفر', value: available, color: net.success),
                    _StatChip(label: 'محجوز', value: reserved, color: net.pending),
                    _StatChip(label: 'مباع', value: sold, color: palette.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: NetSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NetSpacing.md),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontFamily: 'Tajawal'),
              decoration: InputDecoration(
                hintText: 'بحث بالسيريال أو الفئة…',
                hintStyle: TextStyle(fontFamily: 'Tajawal', color: palette.textSecondary),
                prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide(color: palette.border)),
                focusedBorder: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide(color: palette.primary, width: 1.4)),
              ),
            ),
          ),
          const SizedBox(height: NetSpacing.sm),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: NetSpacing.md),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: const Text('الكل', style: TextStyle(fontFamily: 'Tajawal')),
                      selected: _categoryFilter == null,
                      onSelected: (_) => setState(() => _categoryFilter = null),
                    ),
                  ),
                  for (final cat in _categories)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        label: Text(cat.name, style: const TextStyle(fontFamily: 'Tajawal')),
                        selected: _categoryFilter == cat.id,
                        onSelected: (_) => setState(() => _categoryFilter = cat.id),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: NetSpacing.sm),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: NetSpacing.md),
              children: [
                for (final entry in [
                  (null, 'كل الحالات'),
                  (domain.CardStatus.available, 'متوفر'),
                  (domain.CardStatus.reserved, 'محجوز'),
                  (domain.CardStatus.sold, 'مباع'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                      selected: _statusFilter == entry.$1,
                      onSelected: (_) => setState(() => _statusFilter = entry.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NetSpacing.md),
          if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(NetSpacing.xl),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: palette.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    _cards.isEmpty ? 'لا توجد كروت بعد' : 'لا نتائج للبحث/الفلتر',
                    style: TextStyle(fontFamily: 'Tajawal', color: palette.textSecondary),
                  ),
                  if (_cards.isEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openAddCards,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة كروت', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                ],
              ),
            )
          else
            ..._filtered.map((card) {
              final cat = _categories.where((c) => c.id == card.categoryId).firstOrNull;
              final statusColor = switch (card.status) {
                domain.CardStatus.available => net.success,
                domain.CardStatus.reserved => net.pending,
                domain.CardStatus.sold => palette.textSecondary,
              };
              final statusLabel = switch (card.status) {
                domain.CardStatus.available => 'متوفر',
                domain.CardStatus.reserved => 'محجوز',
                domain.CardStatus.sold => 'مباع',
              };
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: NetSpacing.md, vertical: 4),
                child: NetSurfaceCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      card.serial,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (cat != null) cat.name,
                        if (_revealSecrets && (card.secret?.isNotEmpty ?? false)) 'PIN: ${card.secret}',
                        statusLabel,
                      ].join(' · '),
                      style: TextStyle(fontFamily: 'Tajawal', color: palette.textSecondary, fontSize: 12.5),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: NetRadii.pillAll,
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(fontFamily: 'Tajawal', color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 18, color: color),
        ),
        Text(label, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: KayanPalette.of(context).textSecondary)),
      ],
    );
  }
}
