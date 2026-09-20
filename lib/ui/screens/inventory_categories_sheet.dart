import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_sheet.dart';

/// ورقة إدارة فئات الكروت — بطاقات + مخزون + تعديل/تفعيل.
Future<void> showCategoriesSheet({
  required BuildContext context,
  required List<domain.CardCategory> categories,
  required List<domain.Card> cards,
  required Future<void> Function() onChanged,
}) {
  return NetSheet.show<void>(
    context,
    builder: (ctx) => _CategoriesSheet(
      categories: categories,
      cards: cards,
      onChanged: onChanged,
    ),
  );
}

class _CategoriesSheet extends StatefulWidget {
  const _CategoriesSheet({
    required this.categories,
    required this.cards,
    required this.onChanged,
  });

  final List<domain.CardCategory> categories;
  final List<domain.Card> cards;
  final Future<void> Function() onChanged;

  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  Map<String, List<int>> _counts() {
    final map = <String, List<int>>{};
    for (final cat in widget.categories) {
      map[cat.id] = [0, 0, 0, 0];
    }
    for (final card in widget.cards) {
      final cur = map[card.categoryId];
      if (cur == null) continue;
      if (card.status == domain.CardStatus.available) cur[0]++;
      if (card.status == domain.CardStatus.reserved) cur[1]++;
      if (card.status == domain.CardStatus.sold) cur[2]++;
      cur[3] = cur[0] + cur[1] + cur[2];
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final counts = _counts();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(color: palette.surface, borderRadius: NetRadii.sheetTop),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: palette.border, borderRadius: NetRadii.pillAll)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('فئات الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(widget.categories.length.toString() + ' فئة · إدارة القيم والمخزون', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary)),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _editCategory(context, null),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('فئة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.categories.isEmpty
                    ? const AsyncEmptyView(message: 'لا توجد فئات بعد', hint: 'أنشئ فئة بقيمة اسمية موجبة أولًا', icon: Icons.category_outlined, compact: true)
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: widget.categories.length,
                        itemBuilder: (context, i) {
                          final cat = widget.categories[i];
                          final c = counts[cat.id] ?? [0, 0, 0, 0];
                          final major = cat.faceValue.minorUnits / 100.0;
                          final valueLabel = major == major.roundToDouble() ? major.toInt().toString() : major.toStringAsFixed(2);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: palette.surfaceVariant.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _editCategory(context, cat),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: cat.isActive ? palette.primary.withValues(alpha: 0.12) : palette.border.withValues(alpha: 0.4),
                                        child: Text(valueLabel, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, color: cat.isActive ? palette.primary : palette.textSecondary, fontSize: 11)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Expanded(child: Text(cat.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 15))),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: cat.isActive ? const Color(0xFF10B981).withValues(alpha: 0.12) : palette.border.withValues(alpha: 0.35),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(cat.isActive ? 'نشطة' : 'متوقفة', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: cat.isActive ? const Color(0xFF10B981) : palette.textSecondary)),
                                              ),
                                            ]),
                                            const SizedBox(height: 4),
                                            Text(valueLabel + ' ر.ي · متاح ' + c[0].toString() + ' · محجوز ' + c[1].toString() + ' · مباع ' + c[2].toString(), style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'خيارات الفئة',
                                        onSelected: (v) async {
                                          if (v == 'edit') await _editCategory(context, cat);
                                          if (v == 'toggle') await _toggleCategory(cat);
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: 'edit', child: Text('تعديل', style: TextStyle(fontFamily: 'Tajawal'))),
                                          PopupMenuItem(value: 'toggle', child: Text(cat.isActive ? 'إيقاف' : 'تفعيل', style: const TextStyle(fontFamily: 'Tajawal'))),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleCategory(domain.CardCategory cat) async {
    final c = AppScope.of(context);
    final r = await c.catalogService.saveCategory(
      domain.CardCategory(id: cat.id, name: cat.name, faceValue: cat.faceValue, isActive: !cat.isActive),
    );
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure<dynamic>).error.message, style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _editCategory(BuildContext context, domain.CardCategory? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final major = existing == null
        ? ''
        : (existing.faceValue.minorUnits / 100.0).toStringAsFixed(existing.faceValue.minorUnits % 100 == 0 ? 0 : 2);
    final valueCtrl = TextEditingController(text: major);
    var active = existing?.isActive ?? true;
    String? localError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(existing == null ? 'فئة جديدة' : 'تعديل الفئة', style: const TextStyle(fontFamily: 'Tajawal')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الفئة (مثال: كرت 100)', border: OutlineInputBorder()), style: const TextStyle(fontFamily: 'Tajawal')),
                const SizedBox(height: 12),
                TextField(
                  controller: valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'القيمة الاسمية (ر.ي)', border: OutlineInputBorder()),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فئة نشطة', style: TextStyle(fontFamily: 'Tajawal')),
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                ),
                if (localError != null) ...[
                  const SizedBox(height: 6),
                  Text(localError!, style: TextStyle(fontFamily: 'Tajawal', color: context.netColors.rejected, fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final maj = double.tryParse(valueCtrl.text.trim().replaceAll(',', '.'));
                  if (name.isEmpty) {
                    setLocal(() => localError = 'أدخل اسم الفئة');
                    return;
                  }
                  if (maj == null || maj <= 0) {
                    setLocal(() => localError = 'أدخل قيمة اسمية صحيحة أكبر من صفر');
                    return;
                  }
                  final c = AppScope.of(context);
                  final r = await c.catalogService.saveCategory(
                    domain.CardCategory(
                      id: existing?.id ?? '',
                      name: name,
                      faceValue: Money(minorUnits: (maj * 100).round(), currencyCode: existing?.faceValue.currencyCode ?? 'YER'),
                      isActive: active,
                    ),
                  );
                  if (r is Failure) {
                    setLocal(() => localError = (r as Failure<dynamic>).error.message);
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    valueCtrl.dispose();
    await widget.onChanged();
  }
}
