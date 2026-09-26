import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/rejection_codes.dart';
import '../../domain/services/rejected_message_catalog.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';

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

  /// معرّف الرسالة قيد إعادة المحاولة حالياً (لتعطيل زرّها فقط أثناء العمل).
  String? _retryingId;

  /// تبويب الأرشيف — الرسائل التي تمت معالجتها/استعادتها بنجاح (قراءة فقط).
  bool _showArchive = false;
  List<RejectedMessageItem> _archiveItems = const [];

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
    try {
      final c = AppScope.of(context);
      DateTime? viewedAfter;
      final viewed = await c.settings
          .find(SettingKeys.lastRejectedMessagesViewedAt)
          .timeout(const Duration(seconds: 10));
      if (viewed is Success<AppSetting?> && viewed.value != null) {
        viewedAfter = DateTime.tryParse(viewed.value!.value)?.toUtc();
      }
      final catalog = RejectedMessageCatalog(
        messages: c.messages,
        auditLogs: c.auditLogs,
        parser: c.messageParser,
      );
      final result = await catalog.listRejected(viewedAfter: viewedAfter);
      if (result is Failure<List<RejectedMessageItem>>) {
        throw StateError(result.error.message);
      }
      final items = (result as Success<List<RejectedMessageItem>>).value;
      final newCount = items.where((i) => i.isNew).length;
      final archive = <RejectedMessageItem>[];
      for (final status in [
        MessageProcessingStatus.processed,
        MessageProcessingStatus.recovered,
      ]) {
        final r = await c.messages.listByStatus(status).timeout(
          const Duration(seconds: 10),
        );
        if (r is Success<List<IncomingMessage>>) {
          for (final m in r.value) {
            final parse = c.messageParser.parse(m);
            archive.add(
              RejectedMessageItem(
                message: m,
                category: RejectionCategories.all,
                reason: 'تمت معالجة الرسالة بنجاح',
                isNew: false,
                amount: parse is Success<ParsedTransfer> ? parse.value.amount : null,
                phone: parse is Success<ParsedTransfer>
                    ? parse.value.customerIdentifier
                    : m.customerIdentifier,
                reference: parse is Success<ParsedTransfer> ? parse.value.reference : null,
              ),
            );
          }
        }
      }
      archive.sort((a, b) => b.message.receivedAt.compareTo(a.message.receivedAt));
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
        _archiveItems = archive;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الرسائل المرفوضة: $error';
      });
    }
  }

  /// إعادة محاولة رسالة مرفوضة: تعيد تشغيل نفس مسار الاعتماد الكامل الآن
  /// (تحقق من المصدر ثم القالب ثم إيداع). إن نجحت تُعتمد وتختفي من القائمة؛
  /// وإن فشلت تُعرض رسالة السبب الجديد فوراً، وتبقى الرسالة في الأرشيف.
  Future<void> _retry(RejectedMessageItem item) async {
    final id = item.message.id;
    setState(() => _retryingId = id);
    try {
      final result = await AppScope.of(context).pendingReview.retryRejected(id);
      if (!mounted) return;
      if (result is Success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إعادة المعالجة واعتماد الرسالة بنجاح')),
        );
        await _load(markViewed: false);
      } else if (result is Failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّرت إعادة المعالجة: ${(result as Failure).error.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _retryingId = null);
    }
  }

  /// يفتح «بيع مباشر» مع تعبئة الجوال والمبلغ من الرسالة قدر الإمكان، حتى
  /// يستطيع المشغّل تسليم الكرت يدوياً فوراً دون انتظار إصلاح سبب الرفض.
  void _manual(RejectedMessageItem item) {
    final phone = item.phone;
    AppRoutes.openDirectSalePrefilled(
      context,
      phone: phone != null && RegExp(r'^7\d{8}$').hasMatch(phone) ? phone : null,
      amountMinor: item.amount?.minorUnits,
    );
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
          title: const NetAppBarTitle(
            icon: Icons.error_outline_rounded,
            title: 'الرسائل المرفوضة',
            subtitle: 'مراجعة وتحليل الرسائل المرفوضة',
          ),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'أرشيف',
              onPressed: () => setState(() => _showArchive = !_showArchive),
              icon: Icon(
                _showArchive ? Icons.chat_bubble_outline : Icons.inventory_2_outlined,
                color: _showArchive
                    ? context.kayan.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
            if (!_loading && _error == null && !_showArchive) ...[
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
                            ? context.kayan.primary
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _SummaryBanner(
                  total: _items.length,
                  newCount: _newCount,
                ),
              ),
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
                      : _showArchive
                          ? _archiveList()
                          : _filtered.isEmpty
                          ? AsyncEmptyView(
                              message: _items.isEmpty
                                  ? 'لا توجد رسائل مرفوضة'
                                  : 'لا نتائج لهذا التصنيف أو البحث',
                              icon: Icons.archive_outlined,
                            )
                          : RefreshIndicator(
                              color: context.kayan.primary,
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
                                          child: _RejectedCard(
                                            item: item,
                                            busy: _retryingId == item.message.id,
                                            onRetry: item.auditAction == RejectionCodes.duplicateTransaction
                                                ? null
                                                : () => _retry(item),
                                            onManual: () => _manual(item),
                                          ),
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

  Widget _archiveList() {
    final groups = <String, List<RejectedMessageItem>>{};
    for (final i in _archiveItems) {
      final t = i.message.receivedAt.toLocal();
      final key =
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(i);
    }
    final keys = groups.keys.toList();
    if (_archiveItems.isEmpty) {
      return const AsyncEmptyView(
        message: 'لا توجد رسائل محلولة في الأرشيف',
        icon: Icons.inventory_2_outlined,
      );
    }
    return RefreshIndicator(
      color: context.kayan.primary,
      onRefresh: () => _load(markViewed: false),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: keys.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.netColors.successContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${_archiveItems.length} رسالة محلولة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    color: context.netColors.success,
                  ),
                ),
              ),
            );
          }
          final day = keys[i - 1];
          final dayItems = groups[day]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  '$day (${dayItems.length})',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ...dayItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RejectedCard(item: item, archived: true),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.total, required this.newCount});
  final int total;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.netColors.warningContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.netColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.netColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$total رسالة مرفوضة',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
                color: context.netColors.warning,
              ),
            ),
          ),
          if (newCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.netColors.warning,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'جديد $newCount',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({
    required this.item,
    this.archived = false,
    this.busy = false,
    this.onRetry,
    this.onManual,
  });
  final RejectedMessageItem item;
  final bool archived;

  /// أثناء تنفيذ إعادة المحاولة لهذه الرسالة تحديداً (تعطيل زرّيها).
  final bool busy;

  /// null يعني: إعادة المحاولة غير متاحة لهذه الرسالة (مثل التكرار).
  final VoidCallback? onRetry;
  final VoidCallback? onManual;

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour;
    final min = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$min $period';
  }

  String _fmtAmount(Money? m) {
    if (m == null) return '';
    final major = m.minorUnits / 100.0;
    final s = m.minorUnits % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ${m.currencyCode}';
  }

  @override
  Widget build(BuildContext context) {
    final m = item.message;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.reason,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: archived
                        ? context.netColors.success
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
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
          const SizedBox(height: 8),
          Row(
            children: [
              if (m.sender.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.sender,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (item.phone != null && item.phone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  item.phone!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
              if (_fmtAmount(item.amount).isNotEmpty) ...[
                const Spacer(),
                Text(
                  _fmtAmount(item.amount),
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: archived
                        ? context.netColors.success
                        : context.netColors.rejected,
                  ),
                ),
              ],
            ],
          ),
          if (archived) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.netColors.successContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'تمت المعالجة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.netColors.success,
                  ),
                ),
              ),
            ),
          ],
          if (!archived) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRetry,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: context.kayan.primary),
                      foregroundColor: context.kayan.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : onManual,
                    icon: const Icon(Icons.storefront_outlined, size: 16),
                    label: const Text(
                      'معالجة يدوية',
                      style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
