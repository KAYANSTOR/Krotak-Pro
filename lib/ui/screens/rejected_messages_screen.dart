import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/rejected_message_catalog.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// الرسائل المرفوضة — مطابقة إطار الفيديو (`cards_t320s` / `rem_320`).
///
/// - عنوان + عنوان فرعي
/// - شرائح تصنيف أفقية (مكررة / غير صالحة / …)
/// - بطاقة ملخص صفراء: الإجمالي + شارة «جديد»
/// - تجميع بالتاريخ
/// - بطاقة: سبب · وقت · شارة محفظة
/// - Domain: RejectedMessageCatalog + mark viewed
class RejectedMessagesScreen extends StatefulWidget {
  const RejectedMessagesScreen({super.key});

  @override
  State<RejectedMessagesScreen> createState() => _RejectedMessagesScreenState();
}

class _RejectedMessagesScreenState extends State<RejectedMessagesScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<RejectedMessageItem> _items = const [];
  String _filter = RejectionCategories.all;
  int _newCount = 0;

  /// تسميات قصيرة للشرائح مطابقة لنص الفيديو قدر الإمكان.
  static const _chipShort = <String, String>{
    RejectionCategories.all: 'الكل',
    RejectionCategories.duplicateTransfer: 'عملية تحويل مكررة',
    RejectionCategories.templateMismatch: 'تنسيق الرسالة غير صالح',
    RejectionCategories.unresolvedCustomer: 'غير مسجلة',
    RejectionCategories.smsDeliveryFailed: 'فشل إرسال الكود',
    RejectionCategories.outOfStock: 'لا يوجد مخزون',
    RejectionCategories.rejectedFromPending: 'مرفوضة من المعلّقة',
    RejectionCategories.ambiguousCategory: 'فئة غامضة',
    RejectionCategories.unmatchedAmount: 'مبلغ بلا فئة',
    RejectionCategories.other: 'أخرى',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(markViewed: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool markViewed = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);

    DateTime? viewedAfter;
    final viewed = await c.settings.find(SettingKeys.lastRejectedMessagesViewedAt);
    if (viewed is Success<AppSetting?> && viewed.value != null) {
      viewedAfter = DateTime.tryParse(viewed.value!.value)?.toUtc();
    }

    final catalog = RejectedMessageCatalog(
      messages: c.messages,
      auditLogs: c.auditLogs,
      parser: c.messageParser,
    );
    final result = await catalog.listRejected(viewedAfter: viewedAfter);
    if (!mounted) return;
    if (result is Failure<List<RejectedMessageItem>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    final items = (result as Success<List<RejectedMessageItem>>).value;
    final newCount = items.where((i) => i.isNew).length;

    if (markViewed) {
      await c.settings.save(
        AppSetting(
          key: SettingKeys.lastRejectedMessagesViewedAt,
          value: c.clock.now().toUtc().toIso8601String(),
          updatedAt: c.clock.now(),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = items;
      _newCount = newCount;
    });
  }

  List<String> get _availableCategories {
    final set = <String>{RejectionCategories.all};
    for (final i in _items) {
      set.add(i.category);
    }
    const preferred = [
      RejectionCategories.all,
      RejectionCategories.duplicateTransfer,
      RejectionCategories.templateMismatch,
      RejectionCategories.unresolvedCustomer,
      RejectionCategories.smsDeliveryFailed,
      RejectionCategories.outOfStock,
      RejectionCategories.rejectedFromPending,
      RejectionCategories.ambiguousCategory,
      RejectionCategories.unmatchedAmount,
      RejectionCategories.other,
    ];
    final ordered = <String>[];
    for (final p in preferred) {
      if (set.contains(p)) ordered.add(p);
    }
    for (final s in set) {
      if (!ordered.contains(s)) ordered.add(s);
    }
    return ordered;
  }

  List<RejectedMessageItem> get _filtered {
    var list = _items;
    if (_filter != RejectionCategories.all) {
      list = list.where((i) => i.category == _filter).toList(growable: false);
    }
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return list;
    return list
        .where((i) {
          final phone = i.phone ?? '';
          return phone.contains(q) ||
              i.message.sender.contains(q) ||
              i.message.body.contains(q) ||
              i.reason.contains(q);
        })
        .toList(growable: false);
  }

  /// تجميع حسب يوم الاستلام (الأحدث أولاً).
  Map<String, List<RejectedMessageItem>> get _grouped {
    final map = <String, List<RejectedMessageItem>>{};
    for (final i in _filtered) {
      final t = i.message.receivedAt.toLocal();
      final key =
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(i);
    }
    return map;
  }

  String _chipLabel(String cat) => _chipShort[cat] ?? cat;

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    final keys = groups.keys.toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(
              Icons.arrow_forward,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الرسائل المرفوضة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                'مراجعة وتحليل الرسائل المرفوضة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'أرشيف',
              onPressed: () {},
              icon: Icon(
                Icons.inventory_2_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'المزيد',
              onPressed: () => _load(markViewed: false),
              icon: Icon(
                Icons.more_horiz,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_loading && _error == null) ...[
              // شرائح التصنيف — مطابقة الفيديو
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  itemCount: _availableCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cat = _availableCategories[i];
                    final selected = _filter == cat;
                    return ChoiceChip(
                      label: Text(
                        _chipLabel(cat),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      selected: selected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF0F766E)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onSelected: (_) => setState(() => _filter = cat),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
              // بطاقة الملخص الصفراء
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _SummaryBanner(
                  total: _items.length,
                  newCount: _newCount,
                ),
              ),
              // بحث
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                  decoration: InputDecoration(
                    hintText: 'بحث بجوال أو محفظة أو سبب',
                    hintStyle: TextStyle(
                      fontFamily: 'Tajawal',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: () => _load())
                      : _filtered.isEmpty
                          ? AsyncEmptyView(
                              message: _items.isEmpty
                                  ? 'لا توجد رسائل مرفوضة'
                                  : 'لا نتائج لهذا التصنيف أو البحث',
                              icon: Icons.archive_outlined,
                            )
                          : RefreshIndicator(
                              color: const Color(0xFF0F766E),
                              onRefresh: () => _load(markViewed: false),
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: keys.length,
                                itemBuilder: (_, gi) {
                                  final day = keys[gi];
                                  final dayItems = groups[day]!;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          '$day (${dayItems.length})',
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontFamily: 'Tajawal',
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      ...dayItems.map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: _RejectedCard(item: item),
                                        ),
                                      ),
                                    ],
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

/// بطاقة ملخص صفراء مطابقة للفيديو.
class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.total, required this.newCount});

  final int total;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.netColors.warningContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.netColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: context.netColors.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجمالي الرسائل المرفوضة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: context.netColors.warning,
                  ),
                ),
                Text(
                  '$total رسالة مرفوضة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: context.netColors.warning,
                  ),
                ),
              ],
            ),
          ),
          if (newCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.netColors.rejectedContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: context.netColors.rejected.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '$newCount جديد',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: context.netColors.rejected,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة رسالة مرفوضة مطابقة للإطار.
class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.item});

  final RejectedMessageItem item;

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final m = item.message;
    final wallet = m.sender.isEmpty ? '—' : m.sender;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // نقطة رمادية يمين المحتوى (RTL visual)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.reason,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // نقطة حمراء يسار (حافة البطاقة)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: context.netColors.rejected,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // شارة المحفظة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      wallet,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // الوقت
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmtTime(m.receivedAt),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.isNew) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.netColors.rejectedContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'جديد',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.netColors.rejected,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
