import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/card.dart' as domain;
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../async_views.dart';
import '../../theme/net_tokens.dart';
import '../net/net_indicators.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
  int get _soldTotal => _rows.fold<int>(0, (sum, row) => sum + (row.total - row.available - row.reserved));
  int get _maxAvailable =>
      _rows.fold<int>(0, (max, row) => row.available > max ? row.available : max);

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'مخزون الكروت',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onGoToCards,
                    child: const Text(
                      'إدارة',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
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
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                          children: [
                            NetIndicatorGrid(
                              indicators: [
                                NetIndicatorTile(
                                  label: 'كروت متوفرة',
                                  value: '$_availableTotal',
                                  icon: Icons.style_rounded,
                                ),
                                NetIndicatorTile(
                                  label: 'محجوزة',
                                  value: '$_reservedTotal',
                                  icon: Icons.lock_clock_rounded,
                                  tint: context.netColors.reserved,
                                ),
                                NetIndicatorTile(
                                  label: 'مباعة',
                                  value: '$_soldTotal',
                                  icon: Icons.sell_rounded,
                                  tint: context.netColors.sold,
                                ),
                                NetIndicatorTile(
                                  label: 'فئات نشطة',
                                  value: '${_rows.length}',
                                  icon: Icons.category_rounded,
                                  tint: KayanColors.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: NetSpacing.md),
                            Text(
                              'توزيع المخزون المتاح حسب الفئة',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: KayanPalette.of(context).textPrimary,
                              ),
                            ),
                            const SizedBox(height: NetSpacing.xs),
                            ..._rows.map(
                              (row) => _CategoryStockBar(
                                row: row,
                                maxAvailable: _maxAvailable,
                              ),
                            ),
                            if (_reservedCards.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'كروت محجوزة — تدخل يدوي',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._reservedCards.map((card) {
                                final cat = _catsById[card.categoryId];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.lock_clock,
                                    color: context.netColors.warning,
                                  ),
                                  title: Text(
                                    card.serialNumber,
                                    style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    cat?.name ?? card.categoryId,
                                    style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.more_horiz),
                                  onTap: () => _openReservedOps(card),
                                );
                              }),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف فئة في رسم المخزون الأفقي: الاسم · الشريط · المتاح (+ تنبيه الانخفاض).
class _CategoryStockBar extends StatelessWidget {
  const _CategoryStockBar({required this.row, required this.maxAvailable});

  final _CategoryStock row;
  final int maxAvailable;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final faceMajor = row.category.faceValue.minorUnits ~/ 100;
    final label = row.category.name.trim().isNotEmpty
        ? row.category.name
        : 'كرت $faceMajor';

    return NetBarRow(
      label: label,
      value: row.available.toDouble(),
      maxValue: maxAvailable.toDouble(),
      color: row.isLow ? net.error : net.available,
      valueLabel: '${row.available} متاح',
      labelWidth: 84,
      trailing: row.isLow
          ? Padding(
              padding: const EdgeInsets.only(left: NetSpacing.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.sm,
                  vertical: 1,
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
            )
          : null,
    );
  }
}
