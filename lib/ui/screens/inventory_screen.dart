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

class _InventoryScreenState extends State<InventoryScreen> {
  bool _loading = true;
  String? _error;
  List<domain.CardCategory> _categories = const [];
  List<domain.Card> _cards = const [];
  String _query = '';
  String? _categoryFilter;
  domain.CardStatus? _statusFilter;
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
            ? (cats as Failure).error.message
            : (cards as Failure).error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _categories = (cats as Success<List<domain.CardCategory>>).value;
      _cards = (cards as Success<List<domain.Card>>).value;
    });
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
    return list;
  }

  Future<void> _openAddCards() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'أضف فئة أولاً قبل استيراد الكروت',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
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
  }

  void _resetInventoryFilters() {
    setState(() {
      _query = '';
      _categoryFilter = null;
      _statusFilter = null;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: AsyncLoadingView()),
      );
    }
    if (_error != null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AsyncErrorView(message: _error!, onRetry: _load),
        ),
      );
    }

    final filtered = _filtered;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'إدارة الكروت',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'قائمة',
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.category_outlined,
                              color: KayanColors.primary),
                          title: const Text(
                            'إدارة الفئات',
                            style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openCategories();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.cloud_upload_outlined,
                              color: KayanColors.primary),
                          title: const Text(
                            'استيراد كروت',
                            style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openAddCards();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.filter_alt_off_outlined,
                              color: KayanColors.primary),
                          title: const Text(
                            'إلغاء الفلاتر والبحث',
                            style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _resetInventoryFilters();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openAddCards,
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'بحث برقم الكرت أو الرمز',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد كروت',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final card = filtered[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              card.serialNumber,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${card.status.name} • ${card.secretCode.isEmpty ? 'بدون رمز' : 'مع رمز'}',
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
