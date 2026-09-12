import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/rejected_message_catalog.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// الرسائل المرفوضة — مراجعة وأرشفة (PD-08 / B3).
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
      RejectionCategories.smsDeliveryFailed,
      RejectionCategories.outOfStock,
      RejectionCategories.duplicateTransfer,
      RejectionCategories.templateMismatch,
      RejectionCategories.rejectedFromPending,
      RejectionCategories.unresolvedCustomer,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final danger = semantic?.rejected ?? cs.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الرسائل المرفوضة',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => _load(markViewed: false),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'مراجعة وتحليل الرسائل المرفوضة',
              style: TextStyle(
                fontFamily: 'Tajawal',
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          if (!_loading && _error == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SummaryCard(
                total: _items.length,
                newCount: _newCount,
                accent: danger,
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _availableCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = _availableCategories[i];
                  final selected = _filter == cat;
                  final count = cat == RejectionCategories.all
                      ? _items.length
                      : _items.where((e) => e.category == cat).length;
                  return FilterChip(
                    label: Text(
                      count > 0 && cat != RejectionCategories.all
                          ? '$cat ($count)'
                          : cat,
                      style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = cat),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث بجوال أو محفظة أو سبب',
                  hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
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
                                ? 'لا توجد رسائل مرفوضة\nالرسائل المرفوضة بعد المراجعة تظهر هنا للتحليل'
                                : 'لا نتائج لهذا التصنيف أو البحث',
                            icon: Icons.archive_outlined,
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(markViewed: false),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                return _RejectedCard(
                                  item: _filtered[i],
                                  accent: danger,
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.newCount,
    required this.accent,
  });

  final int total;
  final int newCount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: accent.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجمالي المرفوضة',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '$total رسالة',
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            if (newCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$newCount جديد',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    color: cs.onError,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.item, required this.accent});

  final RejectedMessageItem item;
  final Color accent;

  String _fmtAmount(Money? m) {
    if (m == null) return '—';
    final major = m.minorUnits / 100.0;
    return '${major.toStringAsFixed(m.minorUnits % 100 == 0 ? 0 : 2)} ${m.currencyCode}';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = item.message;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.reason,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.category,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.isNew)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'جديد',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.account_balance_wallet_outlined, 'المحفظة', m.sender),
            _line(Icons.phone_android, 'الجوال', item.phone ?? '—'),
            _line(Icons.payments_outlined, 'المبلغ', _fmtAmount(item.amount)),
            if (item.reference != null && item.reference!.isNotEmpty)
              _line(Icons.tag, 'المرجع', item.reference!),
            _line(Icons.schedule, 'الوقت', _fmtTime(m.receivedAt)),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
