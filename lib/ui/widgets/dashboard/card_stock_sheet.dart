import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/card.dart' as domain;
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';
import '../async_views.dart';

class CardStockSheet extends StatefulWidget {
  const CardStockSheet({super.key, required this.onGoToCards});
  final VoidCallback onGoToCards;

  static Future<void> show(BuildContext context, {required VoidCallback onGoToCards}) => showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => CardStockSheet(onGoToCards: onGoToCards));

  @override
  State<CardStockSheet> createState() => _CardStockSheetState();
}

class _CategoryStock {
  const _CategoryStock({required this.category, required this.available, required this.total});
  final domain.CardCategory category;
  final int available;
  final int total;
  bool get isLow => available == 0;
}

class _CardStockSheetState extends State<CardStockSheet> {
  bool _loading = true;
  String? _error;
  List<_CategoryStock> _rows = const [];

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final c = AppScope.of(context);
    final cats = await c.categories.listAll();
    final avail = await c.cards.listByStatus(domain.CardStatus.available);
    final reserved = await c.cards.listByStatus(domain.CardStatus.reserved);
    final sold = await c.cards.listByStatus(domain.CardStatus.sold);
    if (!mounted) return;
    if (cats is Failure) { setState(() { _loading = false; _error = (cats as Failure).error.message; }); return; }
    final categories = (cats as Success<List<domain.CardCategory>>).value;
    final available = avail is Success<List<domain.Card>> ? avail.value : <domain.Card>[];
    final reservedList = reserved is Success<List<domain.Card>> ? reserved.value : <domain.Card>[];
    final soldList = sold is Success<List<domain.Card>> ? sold.value : <domain.Card>[];
    int countFor(List<domain.Card> cards, String categoryId) => cards.where((e) => e.categoryId == categoryId).length;
    final rows = categories.where((e) => e.isActive).map((cat) { final a = countFor(available, cat.id); final t = a + countFor(reservedList, cat.id) + countFor(soldList, cat.id); return _CategoryStock(category: cat, available: a, total: t); }).toList();
    setState(() { _loading = false; _rows = rows; });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Directionality(textDirection: TextDirection.rtl, child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      decoration: BoxDecoration(color: palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 48, height: 5, decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(50))),
        Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 12), child: Text('مخزون الكروت حسب الفئة', style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary))),
        if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: AsyncLoadingView(message: 'جاري تحميل المخزون…'))
        else if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24), child: AsyncErrorView(message: _error!, onRetry: _load))
        else if (_rows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24), child: Text('لا توجد فئات مسجلة', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontSize: 14, color: palette.textSecondary)))
        else Flexible(child: ListView.separated(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), itemCount: _rows.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, i) => _CategoryStockTile(row: _rows[i]))),
        const Divider(height: 1),
        Padding(padding: EdgeInsets.fromLTRB(24, 16, 24, 12 + bottom), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('إجمالي الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 14, color: palette.textSecondary)),
            Text('${_rows.fold<int>(0, (s, e) => s + e.available)} متوفر من ${_rows.fold<int>(0, (s, e) => s + e.total)}', style: TextStyle(fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: KayanColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () { Navigator.of(context).pop(); widget.onGoToCards(); },
            icon: const Icon(Icons.inventory_2_outlined, size: 20),
            label: const Text('الذهاب إلى إدارة الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 15, fontWeight: FontWeight.bold)),
          )),
        ])),
      ]),
    ));
  }
}

class _CategoryStockTile extends StatelessWidget {
  const _CategoryStockTile({required this.row});
  final _CategoryStock row;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final faceMajor = row.category.faceValue.minorUnits ~/ 100;
    final label = row.category.name.trim().isNotEmpty ? row.category.name : 'كرت $faceMajor';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: row.isLow ? KayanColors.error : KayanColors.primary, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontFamily: 'Tajawal', fontSize: 15, fontWeight: FontWeight.w600, color: palette.textPrimary))),
      Text('${row.available} / ${row.total}', style: TextStyle(fontFamily: 'Tajawal', fontSize: 14, color: palette.textSecondary)),
      if (row.isLow) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: KayanColors.errorBackground, borderRadius: BorderRadius.circular(8)), child: const Text('منخفض', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, fontWeight: FontWeight.bold, color: KayanColors.error)))],
    ]));
  }
}
