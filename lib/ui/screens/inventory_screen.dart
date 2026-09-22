import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'sold_cards_sheet.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/services/card_import_file_reader.dart';
import '../../domain/services/card_import_parser.dart';
import '../../domain/services/card_import_preview.dart';
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

  /// وضع التحديد المتعدد — يُفعَّل بالضغط المطوّل على أي كرت.
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

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
    // الاستيراد والحذف يغيّران المخزون: نُزامن إشعار أندرويد الحي فوراً (يظهر عند
    // الهبوط تحت العتبة، ويُلغى فقط بعد إعادة التعبئة فوقها).
    await c.lowStockAlerts.syncDeviceAlert();
  }

  List<domain.Card> get _filtered {
    var list = _cards;
    if (_categoryFilter != null) {
      list = list.where((e) => e.categoryId == _categoryFilter).toList();
    }
    if (_statusFilter != null) {
      list = list.where((e) => e.status == _statusFilter).toList();
    }
    final q = _query.trim();
    if (q.isNotEmpty) {
      list = list
          .where((e) =>
              e.serialNumber.contains(q) ||
              e.secretCode.contains(q) ||
              e.id.contains(q))
          .toList();
    }
    // ترتيب العرض: المتاح في الأعلى ثم المحجوز، والمباع في الأسفل.
    final ordered = List<domain.Card>.of(list);
    ordered.sort((a, b) {
      final byRank = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (byRank != 0) return byRank;
      return a.serialNumber.compareTo(b.serialNumber);
    });
    return ordered;
  }

  /// ترتيب حالات الكرت في القائمة — المتاح أولاً والمباع آخراً.
  static int _statusRank(domain.CardStatus status) => switch (status) {
        domain.CardStatus.available => 0,
        domain.CardStatus.reserved => 1,
        domain.CardStatus.disabled => 2,
        domain.CardStatus.expired => 3,
        domain.CardStatus.sold => 4,
      };

  /// Display-only counts per category/status over the already-loaded cards.
  int _countFor(String categoryId, domain.CardStatus status) => _cards
      .where((e) => e.categoryId == categoryId && e.status == status)
      .length;

  String _categoryName(String categoryId) {
    for (final cat in _categories) {
      if (cat.id == categoryId) return cat.name;
    }
    return categoryId;
  }

  Future<void> _openAddCards() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'أضف فئة أولاً قبل استيراد الكروت',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
        ),
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

  Future<void> _openSoldCards() async {
    await showSoldCardsSheet(
      context: context,
      categories: _categories,
      onChanged: _load,
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
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _enterSelection(String cardId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(cardId);
    });
  }

  void _toggleSelection(String cardId) {
    setState(() {
      if (!_selectedIds.remove(cardId)) _selectedIds.add(cardId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectionMode = true;
      _selectedIds.addAll(_filtered.map((e) => e.id));
    });
  }

  /// حذف كرت واحد أو عدة كروت — لا يتم أي حذف قبل تأكيد صريح من المستخدم.
  Future<void> _deleteCards(List<String> ids) async {
    final targets = _cards.where((e) => ids.contains(e.id)).toList(growable: false);
    if (targets.isEmpty) return;
    final confirmed = await showDeleteCardsConfirm(
      context: context,
      cards: targets,
      categoryNameOf: _categoryName,
    );
    if (!confirmed || !mounted) return;
    final c = AppScope.of(context);
    final r = await c.catalogService.deleteCards(cardIds: ids);
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (r as Failure<dynamic>).error.message,
            style: const TextStyle(fontFamily: NetTypography.family),
          ),
        ),
      );
      return;
    }
    final deleted = (r as Success<int>).value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تمت معالجة $deleted كرت (حذف أو تعطيل المباع)',
          style: const TextStyle(fontFamily: NetTypography.family),
        ),
      ),
    );
    _exitSelection();
    await _load();
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
            title: const Text('إلغاء الفلاتر والبحث'),
            onTap: () {
              Navigator.pop(ctx);
              _resetInventoryFilters();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AsyncLoadingView(skeleton: true, skeletonCount: 5);
    }
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }

    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final filtered = _filtered;
    final available = _cards.where((e) => e.status == domain.CardStatus.available).length;
    final reserved = _cards.where((e) => e.status == domain.CardStatus.reserved).length;
    final sold = _cards.where((e) => e.status == domain.CardStatus.sold).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectionMode)
          NetTabHeader(
            title: 'تم تحديد ' + _selectedIds.length.toString(),
            subtitle: 'اضغط أي كرت لإضافته أو إزالته من التحديد · حذف الكروت لا يمس السجلات المالية',
            icon: Icons.checklist_rounded,
            actions: [
              NetHeaderAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'حذف المحدد',
                color: net.rejected,
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _deleteCards(_selectedIds.toList()),
              ),
              NetHeaderAction(
                icon: Icons.close_rounded,
                tooltip: 'إلغاء التحديد',
                onPressed: _exitSelection,
              ),
            ],
          )
        else
          NetTabHeader(
            title: 'إدارة الكروت',
            subtitle: 'المخزون والحالات والفئات · ' + _cards.length.toString() + ' كرت',
            icon: Icons.style_rounded,
            actions: [
              NetHeaderAction(
                icon: Icons.add_rounded,
                tooltip: 'استيراد كروت',
                onPressed: _openAddCards,
              ),
              NetHeaderAction(
                icon: Icons.more_horiz_rounded,
                tooltip: 'خيارات',
                onPressed: _openOverflowMenu,
              ),
            ],
          ),
        // مطابقة الفيديو: أزرار ظاهرة «الفئات» + «استيراد من ملف»
        if (!_selectionMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(NetSpacing.lg, 0, NetSpacing.lg, NetSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openCategories,
                    icon: const Icon(Icons.category_rounded, size: 20),
                    label: const Text(
                      'الفئات',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openAddCards,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                    label: const Text(
                      'استيراد من ملف',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(NetSpacing.lg, 0, NetSpacing.lg, NetSpacing.sm),
            child: OutlinedButton.icon(
              onPressed: _openSoldCards,
              icon: const Icon(Icons.sell_outlined, size: 20),
              label: const Text(
                'الكروت المباعة — فلاتر وتصدير',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        if (_selectionMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(NetSpacing.lg, 0, NetSpacing.lg, NetSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectAllVisible,
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    label: const Text(
                      'تحديد كل المعروض',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _deleteCards(_selectedIds.toList()),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text(
                      'حذف المحدد',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: net.rejected,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: NetSpacing.pageH,
          child: NetSurfaceCard(
            padding: NetSpacing.cardTight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _LegendDot(color: net.available, label: 'متاح', value: available),
                    const SizedBox(width: NetSpacing.md),
                    _LegendDot(color: net.reserved, label: 'محجوز', value: reserved),
                    const SizedBox(width: NetSpacing.md),
                    _LegendDot(color: net.sold, label: 'مباع', value: sold),
                  ],
                ),
                const SizedBox(height: NetSpacing.md),
                NetRatioBar(
                  segments: [
                    (value: available, color: net.available),
                    (value: reserved, color: net.reserved),
                    (value: sold, color: net.sold),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                right: NetSpacing.lg,
                left: NetSpacing.lg,
                top: NetSpacing.md,
              ),
              children: [
                for (final cat in _categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: NetSpacing.sm),
                    child: FilterChip(
                      selected: _categoryFilter == cat.id,
                      showCheckmark: false,
                      label: Text(
                        cat.name + ' (' + _countFor(cat.id, domain.CardStatus.available).toString() + ')',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _categoryFilter == cat.id ? Colors.white : palette.textPrimary,
                        ),
                      ),
                      selectedColor: palette.primary,
                      backgroundColor: palette.surface,
                      side: BorderSide(
                        color: _categoryFilter == cat.id ? palette.primary : palette.border,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: NetRadii.pillAll),
                      onSelected: (_) => setState(() {
                        _categoryFilter = _categoryFilter == cat.id ? null : cat.id;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NetSpacing.lg,
            NetSpacing.md,
            NetSpacing.lg,
            NetSpacing.sm,
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'بحث برقم الكرت أو الرمز',
              hintStyle: TextStyle(
                fontFamily: NetTypography.family,
                color: palette.textTertiary,
                fontSize: 13,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
              suffixIcon: IconButton(
                tooltip: _revealSecrets ? 'إخفاء الرموز' : 'إظهار الرموز',
                icon: Icon(
                  _revealSecrets ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
                onPressed: () => setState(() => _revealSecrets = !_revealSecrets),
              ),
              filled: true,
              fillColor: palette.surface,
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
            style: TextStyle(fontFamily: NetTypography.family, color: palette.textPrimary),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? AsyncEmptyView(
                  message: _cards.isEmpty ? 'لا توجد كروت بعد' : 'لا نتائج مطابقة',
                  icon: Icons.style_outlined,
                  hint: _cards.isEmpty
                      ? 'أضف فئة أولاً ثم استورد الكروت يدويًا أو من ملف'
                      : 'جرّب إلغاء الفلاتر أو تغيير كلمة البحث',
                  actionLabel: _cards.isEmpty ? 'استيراد كروت' : 'إلغاء الفلاتر',
                  onAction: _cards.isEmpty ? _openAddCards : _resetInventoryFilters,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: palette.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: NetSpacing.sm),
                    itemBuilder: (_, index) {
                      final card = filtered[index];
                      return _CardRow(
                        card: card,
                        categoryName: _categoryName(card.categoryId),
                        revealSecret: _revealSecrets,
                        selectionMode: _selectionMode,
                        selected: _selectedIds.contains(card.id),
                        onTap: _selectionMode ? () => _toggleSelection(card.id) : null,
                        onLongPress: () => _enterSelection(card.id),
                        onDelete: () => _deleteCards([card.id]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: NetSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(width: NetSpacing.xxs),
        Text(
          value.toString(),
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.categoryName,
    required this.revealSecret,
    this.selectionMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  final domain.Card card;
  final String categoryName;
  final bool revealSecret;

  /// وضع التحديد المتعدد: يُستبدل شعار الحالة بمربع تحديد.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// حذف هذا الكرت وحده (يفتح تأكيد الحذف).
  final VoidCallback? onDelete;

  static IconData _statusIcon(domain.CardStatus status) => switch (status) {
        domain.CardStatus.available => Icons.check_circle_outline_rounded,
        domain.CardStatus.reserved => Icons.lock_clock_rounded,
        domain.CardStatus.sold => Icons.sell_outlined,
        domain.CardStatus.disabled => Icons.block_rounded,
        domain.CardStatus.expired => Icons.hourglass_disabled_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final statusColor = cardStatusColor(card.status, net);
    final statusBg = cardStatusContainer(card.status, net);
    final hasSecret = card.secretCode.isNotEmpty;
    final masked = hasSecret
        ? (revealSecret ? card.secretCode : '•' * card.secretCode.length.clamp(4, 10))
        : 'بدون رمز';

    return NetSurfaceCard(
      margin: NetSpacing.pageH,
      padding: const EdgeInsets.all(NetSpacing.md),
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? palette.primary : null,
      child: Row(
        children: [
          if (selectionMode)
            Container(
              width: NetSizes.badge,
              height: NetSizes.badge,
              decoration: BoxDecoration(
                color: selected ? palette.primary : palette.surfaceVariant,
                borderRadius: NetRadii.smAll,
                border: Border.all(
                  color: selected ? palette.primary : palette.border,
                  width: 1.4,
                ),
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.circle_outlined,
                size: 20,
                color: selected ? Colors.white : palette.textTertiary,
              ),
            )
          else
            Container(
              width: NetSizes.badge,
              height: NetSizes.badge,
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: NetRadii.smAll,
              ),
              child: Icon(_statusIcon(card.status), size: 20, color: statusColor),
            ),
          const SizedBox(width: NetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        card.serialNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NetSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: NetRadii.pillAll,
                      ),
                      child: Text(
                        cardStatusLabel(card.status),
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NetSpacing.xxs),
                Row(
                  children: [
                    Icon(Icons.category_rounded, size: 13, color: palette.textTertiary),
                    const SizedBox(width: NetSpacing.xs),
                    Flexible(
                      child: Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: NetSpacing.md),
                    Icon(Icons.vpn_key_rounded, size: 13, color: palette.textTertiary),
                    const SizedBox(width: NetSpacing.xs),
                    Text(
                      masked,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 12,
                        letterSpacing: revealSecret ? 0.2 : 1.2,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!selectionMode && onDelete != null)
            IconButton(
              tooltip: 'حذف الكرت',
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: net.rejected),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
