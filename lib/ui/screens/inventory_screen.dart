import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/dashboard/card_stock_sheet.dart';
import '../widgets/reserved_card_ops.dart';

/// شاشة مخزون الكروت (تبويب الكروت).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _available = const [];
  List<domain.Card> _reserved = const [];

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
    if (!mounted) return;
    if (cats is Failure) {
      setState(() {
        _loading = false;
        _error = (cats as Failure).error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _categories = (cats as Success<List<domain.CardCategory>>).value;
      _available = avail is Success<List<domain.Card>> ? avail.value : const [];
      _reserved = reserved is Success<List<domain.Card>> ? reserved.value : const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الكروت', style: TextStyle(fontFamily: 'Tajawal')),
          actions: [
            IconButton(
              tooltip: 'ملخص المخزون',
              onPressed: () => CardStockSheet.show(context, onGoToCards: () {}),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        Text(
                          'متاح: ${_available.length} · محجوز: ${_reserved.length}',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._categories.where((e) => e.isActive).map((cat) {
                          final a = _available.where((c) => c.categoryId == cat.id).length;
                          final r = _reserved.where((c) => c.categoryId == cat.id).length;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.sim_card_outlined, color: KayanColors.primary),
                            title: Text(cat.name, style: const TextStyle(fontFamily: 'Tajawal')),
                            subtitle: Text(
                              'متاح $a · محجوز $r',
                              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                            ),
                          );
                        }),
                        if (_reserved.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'كروت محجوزة',
                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                          ),
                          ..._reserved.map((card) {
                            domain.CardCategory? cat;
                            for (final c in _categories) {
                              if (c.id == card.categoryId) {
                                cat = c;
                                break;
                              }
                            }
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(card.serialNumber, style: const TextStyle(fontFamily: 'Tajawal')),
                              subtitle: Text(cat?.name ?? card.categoryId, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                              trailing: const Icon(Icons.more_horiz),
                              onTap: cat == null
                                  ? null
                                  : () => showReservedCardOps(
                                        context: context,
                                        card: card,
                                        category: cat!,
                                        onDone: _load,
                                      ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
