import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/card.dart' as domain;
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
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
                            ..._rows.map((row) => _CategoryStockTile(row: row)),
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

class _CategoryStockTile extends StatelessWidget {
  const _CategoryStockTile({required this.row});
  final _CategoryStock row;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final faceMajor = row.category.faceValue.minorUnits ~/ 100;
    final label = row.category.name.trim().isNotEmpty
        ? row.category.name
        : 'كرت $faceMajor';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: row.isLow ? KayanColors.error : KayanColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            '${row.available} متاح',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: palette.textSecondary,
            ),
          ),
          if (row.reserved > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${row.reserved} محجوز',
              style: const TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: context.netColors.warning,
              ),
            ),
          ],
          if (row.isLow) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'منخفض',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
