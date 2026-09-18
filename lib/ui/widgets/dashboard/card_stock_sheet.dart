import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/card.dart' as domain;
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../async_views.dart';
import '../reserved_card_ops.dart';

class CardStockSheet extends StatefulWidget {
  const CardStockSheet({super.key, required this.onGoToCards});
  final VoidCallback onGoToCards;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGoToCards,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CardStockSheet(onGoToCards: onGoToCards),
      );

  @override
  State<CardStockSheet> createState() => _CardStockSheetState();
}

class _CategoryStock {
  const _CategoryStock({
    required this.category,
    required this.available,
    required this.reserved,
    required this.total,
  });
  final domain.CardCategory category;
  final int available;
  final int reserved;
  final int total;
  bool get isLow => available == 0;
}

class _CardStockSheetState extends State<CardStockSheet> {
  bool _loading = true;
  String? _error;
  List<_CategoryStock> _rows = const [];
  List<domain.Card> _reservedCards = const [];
  Map<String, domain.CardCategory> _catsById = const {};

  /// ألوان نقاط الفئات — لوحة محدودة ثابتة الترتيب (عرض فقط).
  static const _dotPalette = <Color>[
    Color(0xFFDB2777),
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
  ];

  Color _dotFor(int index) => _dotPalette[index % _dotPalette.length];

  @override
  void initState() {
    super.initState();
    _CardStockSheetScope.attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _CardStockSheetScope.detach(this);
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
    if (cats is Failure) {
      setState(() {
        _loading = false;
        _error = (cats as Failure).error.message;
      });
      return;
    }
    final categories = (cats as Success<List<domain.CardCategory>>).value;
    final available =
        avail is Success<List<domain.Card>> ? avail.value : <domain.Card>[];
    final reservedList =
        reserved is Success<List<domain.Card>> ? reserved.value : <domain.Card>[];
    final soldList =
        sold is Success<List<domain.Card>> ? sold.value : <domain.Card>[];
    int countFor(List<domain.Card> cards, String categoryId) =>
        cards.where((e) => e.categoryId == categoryId).length;
    final byId = {for (final cat in categories) cat.id: cat};
    final rows = categories
        .where((e) => e.isActive)
        .map((cat) {
          final a = countFor(available, cat.id);
          final r = countFor(reservedList, cat.id);
          final t = a + r + countFor(soldList, cat.id);
          return _CategoryStock(
            category: cat,
            available: a,
            reserved: r,
            total: t,
          );
        })
        .toList(growable: false);
    setState(() {
      _loading = false;
      _rows = rows;
      _reservedCards = reservedList;
      _catsById = byId;
    });
  }

  int get _availableTotal =>
      _rows.fold<int>(0, (sum, row) => sum + row.available);
  int get _reservedTotal =>
      _rows.fold<int>(0, (sum, row) => sum + row.reserved);
  int get _soldTotal => _rows.fold<int>(
      0, (sum, row) => sum + (row.total - row.available - row.reserved));
  int get _lowCount => _rows.where((row) => row.isLow).length;

  Future<void> _openReservedOps(domain.Card card) async {
    final cat = _catsById[card.categoryId];
    if (cat == null) return;
    await showReservedCardOps(
      context: context,
      card: card,
      category: cat,
      onDone: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: NetRadii.sheetTop,
        ),
        child: Column(
          children: [
            const SizedBox(height: NetSpacing.sm),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.xl,
                NetSpacing.md,
                NetSpacing.xl,
                NetSpacing.sm,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'مخزون الكروت حسب الفئة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            NetSpacing.xl,
                            0,
                            NetSpacing.xl,
                            NetSpacing.lg + bottom,
                          ),
                          children: [
                            // ── صفوف الفئات: نقطة · الاسم · شارة منخفض · العدّاد · شريط ──
                            ..._rows.asMap().entries.map(
                                  (entry) => _CategoryStockRow(
                                    row: entry.value,
                                    dotColor: _dotFor(entry.key),
                                    maxAvailable: _maxAvailable,
                                  ),
                                ),
                            if (_rows.isEmpty) ...[
                              const SizedBox(height: NetSpacing.xl),
                              Center(
                                child: Text(
                                  'لا توجد فئات كروت نشطة بعد',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 13,
                                    color: palette.textTertiary,
                                  ),
                                ),
                              ),
                            ],

                            // ── كروت محجوزة — تدخل يدوي (نفس العمليات الحالية) ──
                            if (_reservedCards.isNotEmpty) ...[
                              const SizedBox(height: NetSpacing.lg),
                              Row(
                                children: [
                                  Icon(
                                    Icons.lock_clock_rounded,
                                    size: NetSizes.iconSm,
                                    color: context.netColors.reserved,
                                  ),
                                  const SizedBox(width: NetSpacing.xs),
                                  Text(
                                    'كروت محجوزة — تدخل يدوي',
                                    style: TextStyle(
                                      fontFamily: NetTypography.family,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: NetSpacing.xs),
                              ..._reservedCards.map(
                                (card) => _ReservedCardTile(card),
                              ),
                            ],
                          ],
                        ),
            ),
            // ── ذيل الورقة: إجمالي + الانتقال إلى الإدارة ──
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: palette.border),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                NetSpacing.xl,
                NetSpacing.md,
                NetSpacing.xl,
                NetSpacing.md + (bottom > 0 ? bottom : 0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'إجمالي المخزون',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$_availableTotal متوفر · $_reservedTotal محجوز · $_soldTotal مباع',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (_lowCount > 0) ...[
                    const SizedBox(height: NetSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: context.netColors.error,
                        ),
                        const SizedBox(width: NetSpacing.xs),
                        Expanded(
                          child: Text(
                            'تنبيه: $_lowCount من الفئات نفد مخزونها بالكامل!',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.netColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: NetSpacing.md),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onGoToCards();
                    },
                    icon: const Icon(Icons.inventory_2_rounded, size: 20),
                    label: const Text('الذهاب إلى إدارة الكروت'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _maxAvailable =>
      _rows.fold<int>(0, (max, row) => row.available > max ? row.available : max);
}

/// جسر وصول ثابت من صفوف القائمة إلى حالة الورقة (عرض فقط).
abstract final class _CardStockSheetScope {
  static _CardStockSheetState? _state;

  static void attach(_CardStockSheetState state) => _state = state;
  static void detach(_CardStockSheetState state) {
    if (identical(_state, state)) _state = null;
  }

  static void openReservedOps(BuildContext context, domain.Card card) {
    _state?._openReservedOps(card);
  }

  static String categoryName(BuildContext context, String categoryId) {
    final state = _state;
    final name = state?._catsById[categoryId]?.name;
    if (name != null && name.trim().isNotEmpty) return name;
    return categoryId;
  }
}

/// صف كرت محجوز — يفتح ورقة العمليات المحجوزة الحالية دون أي تغيير منطقي.
class _ReservedCardTile extends StatelessWidget {
  const _ReservedCardTile(this.card);

  final domain.Card card;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NetSpacing.xs),
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: NetRadii.mdAll,
        child: InkWell(
          borderRadius: NetRadii.mdAll,
          onTap: () => _CardStockSheetScope.openReservedOps(context, card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_clock_rounded,
                  size: NetSizes.iconMd,
                  color: net.reserved,
                ),
                const SizedBox(width: NetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.serialNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        _CardStockSheetScope.categoryName(context, card.categoryId),
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 11.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  size: NetSizes.iconSm,
                  color: palette.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// صف فئة واحد على نمط الصورة: نقطة ملونة · القيمة · شارة منخفض · عدّاد · شريط.
class _CategoryStockRow extends StatelessWidget {
  const _CategoryStockRow({
    required this.row,
    required this.dotColor,
    required this.maxAvailable,
  });

  final _CategoryStock row;
  final Color dotColor;
  final int maxAvailable;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final palette = KayanPalette.of(context);
    final faceMajor = row.category.faceValue.minorUnits ~/ 100;
    final label = row.category.name.trim().isNotEmpty
        ? row.category.name
        : 'كرت $faceMajor';
    final fillFactor =
        maxAvailable <= 0 ? 0.0 : (row.available / maxAvailable).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (row.isLow) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: net.errorContainer,
                    borderRadius: NetRadii.pillAll,
                  ),
                  child: Text(
                    'منخفض',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: net.error,
                    ),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
              ],
              Text(
                '${row.available} / ${row.total}',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          ClipRRect(
            borderRadius: NetRadii.pillAll,
            child: SizedBox(
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: palette.surfaceVariant),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: fillFactor,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: dotColor),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
