import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

/// سجل العمليات — مطابقة إطارات الفيديو (`frame_t500s` / `inv_t480s`).
///
/// - بحث + فلاتر أنواع/تواريخ
/// - ملخص: عدد · صافي · إيداعات · صرف
/// - بطاقات عملية مع مبلغ ونوع ووقت
/// - ورقة تصفية حسب نوع العملية (مجموعات الفيديو)
/// - Domain: transactions.listRecent
class TransactionsLogScreen extends StatefulWidget {
  const TransactionsLogScreen({super.key});

  @override
  State<TransactionsLogScreen> createState() => _TransactionsLogScreenState();
}

class _TransactionsLogScreenState extends State<TransactionsLogScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Transaction> _all = const [];
  DateTime? _from;
  DateTime? _to;
  final Set<TransactionType> _typeFilter = {};

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
    final r = await c.transactions.listRecent(limit: 500);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<List<Transaction>>) {
        _all = r.value;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  List<Transaction> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _all.where((tx) {
      final t = tx.createdAt.toLocal();
      if (_from != null) {
        final start = DateTime(_from!.year, _from!.month, _from!.day);
        if (t.isBefore(start)) return false;
      }
      if (_to != null) {
        final end = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
        if (t.isAfter(end)) return false;
      }
      if (_typeFilter.isNotEmpty && !_typeFilter.contains(tx.type)) {
        return false;
      }
      if (q.isEmpty) return true;
      final ref = (tx.reference ?? '').toLowerCase();
      final id = tx.id.toLowerCase();
      final type = _typeLabel(tx.type).toLowerCase();
      return ref.contains(q) || id.contains(q) || type.contains(q);
    }).toList(growable: false);
  }

  int get _depositSum {
    var s = 0;
    for (final tx in _filtered) {
      if (_isInflow(tx.type)) s += tx.amount.minorUnits;
    }
    return s;
  }

  int get _outflowSum {
    var s = 0;
    for (final tx in _filtered) {
      if (!_isInflow(tx.type)) s += tx.amount.minorUnits;
    }
    return s;
  }

  int get _net => _depositSum - _outflowSum;

  bool _isInflow(TransactionType t) =>
      t == TransactionType.deposit || t == TransactionType.reward;

  String _fmtMinor(int minor) {
    final major = minor / 100.0;
    final s = minor % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ر.ي';
  }

  String _fmtSigned(int minor, {required bool positive}) {
    final major = minor / 100.0;
    final s = minor % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return positive ? '+$s ر.ي' : '-$s ر.ي';
  }

  static String _typeLabel(TransactionType t) => switch (t) {
        TransactionType.deposit => 'إيداع / تحويل',
        TransactionType.withdrawal => 'خصم يدوي مباشر',
        TransactionType.sale => 'صرف كرت',
        TransactionType.settlement => 'تسوية حساب نقطة بيع',
        TransactionType.reversal => 'إلغاء / عكس',
        TransactionType.advance => 'صرف كرت سلفني (آجل)',
        TransactionType.reward => 'صرف كرت مكافأة ترويجية',
      };

  Future<void> _openTypeSheet() async {
    final selected = Set<TransactionType>.from(_typeFilter);
    final applied = await showModalBottomSheet<Set<TransactionType>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TypeFilterSheet(initial: selected),
    );
    if (applied != null && mounted) {
      setState(() {
        _typeFilter
          ..clear()
          ..addAll(applied);
      });
    }
  }

  Future<void> _openDateSheet() async {
    final result = await showModalBottomSheet<Map<String, DateTime?>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DateFilterSheet(from: _from, to: _to),
    );
    if (result != null && mounted) {
      setState(() {
        _from = result['from'];
        _to = result['to'];
      });
    }
  }

  void _clearAll() {
    setState(() {
      _from = null;
      _to = null;
      _typeFilter.clear();
      _searchCtrl.clear();
    });
  }

  bool get _hasFilters =>
      _from != null || _to != null || _typeFilter.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F9F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward, color: Color(0xFF0F172A)),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سجل العمليات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'عرض وتصفية جميع المعاملات المسجلة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'تصفية الأنواع',
              onPressed: _openTypeSheet,
              icon: const Icon(Icons.filter_list, color: Color(0xFF0F766E)),
            ),
            IconButton(
              tooltip: 'خيارات متقدمة',
              onPressed: () async {
                final choice = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'خيارات التصفية المتقدمة',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.calendar_month,
                                color: Color(0xFF0F766E)),
                            title: const Text(
                              'نطاق التاريخ',
                              style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'اختر تاريخ البداية والنهاية',
                              style: TextStyle(
                                  fontFamily: 'Tajawal', fontSize: 12),
                            ),
                            onTap: () => Navigator.pop(ctx, 'date'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.category_outlined,
                                color: Color(0xFF0F766E)),
                            title: const Text(
                              'نوع العملية',
                              style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              _typeFilter.isEmpty
                                  ? 'كل الأنواع'
                                  : '${_typeFilter.length} أنواع محددة',
                              style: const TextStyle(
                                  fontFamily: 'Tajawal', fontSize: 12),
                            ),
                            onTap: () => Navigator.pop(ctx, 'type'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                if (choice == 'date') await _openDateSheet();
                if (choice == 'type') await _openTypeSheet();
              },
              icon: const Icon(Icons.tune, color: Color(0xFF0F766E)),
            ),
          ],
        ),
        body: Column(
          children: [
            // بحث
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'Tajawal'),
                decoration: InputDecoration(
                  hintText: 'بحث برقم الجوال، الاسم، رقم الكرت، الحوالة...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                  prefixIcon:
                      const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
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
            // شرائح الفلاتر
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  if (_hasFilters)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.close, size: 16),
                        label: const Text(
                          'مسح الكل',
                          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                        ),
                        onPressed: _clearAll,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      selected: _typeFilter.isNotEmpty,
                      showCheckmark: false,
                      label: Text(
                        _typeFilter.isEmpty
                            ? 'كل الأنواع'
                            : '${_typeFilter.length} أنواع',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _typeFilter.isNotEmpty
                              ? Colors.white
                              : const Color(0xFF334155),
                        ),
                      ),
                      selectedColor: const Color(0xFF0F766E),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: _typeFilter.isNotEmpty
                            ? const Color(0xFF0F766E)
                            : const Color(0xFFE2E8F0),
                      ),
                      onSelected: (_) => _openTypeSheet(),
                    ),
                  ),
                  FilterChip(
                    selected: _from != null || _to != null,
                    showCheckmark: false,
                    label: Text(
                      (_from == null && _to == null)
                          ? 'كل التواريخ'
                          : 'تواريخ محددة',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (_from != null || _to != null)
                            ? Colors.white
                            : const Color(0xFF334155),
                      ),
                    ),
                    selectedColor: const Color(0xFF0F766E),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: (_from != null || _to != null)
                          ? const Color(0xFF0F766E)
                          : const Color(0xFFE2E8F0),
                    ),
                    avatar: Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: (_from != null || _to != null)
                          ? Colors.white
                          : const Color(0xFF64748B),
                    ),
                    onSelected: (_) => _openDateSheet(),
                  ),
                ],
              ),
            ),
            // ملخص
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _SummaryBar(
                  count: items.length,
                  netLabel: _fmtSigned(_net.abs(), positive: _net >= 0),
                  depositLabel: _fmtSigned(_depositSum, positive: true),
                  outflowLabel: _fmtSigned(_outflowSum, positive: false),
                ),
              ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : items.isEmpty
                          ? const AsyncEmptyView(
                              message: 'لا عمليات في الفترة/التصفية المحددة',
                              icon: Icons.receipt_long_outlined,
                            )
                          : RefreshIndicator(
                              color: const Color(0xFF0F766E),
                              onRefresh: _load,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) => _TxCard(
                                  tx: items[i],
                                  label: _typeLabel(items[i].type),
                                  inflow: _isInflow(items[i].type),
                                  amountLabel: _fmtMinor(items[i].amount.minorUnits),
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.count,
    required this.netLabel,
    required this.depositLabel,
    required this.outflowLabel,
  });

  final int count;
  final String netLabel;
  final String depositLabel;
  final String outflowLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count عملية',
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'الصافي: $netLabel',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_downward,
                              size: 14, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text(
                            'إجمالي الإيداعات',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        depositLabel,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_upward,
                              size: 14, color: Color(0xFFDC2626)),
                          SizedBox(width: 4),
                          Text(
                            'إجمالي الصرف / الخصم',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        outflowLabel,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  const _TxCard({
    required this.tx,
    required this.label,
    required this.inflow,
    required this.amountLabel,
  });

  final Transaction tx;
  final String label;
  final bool inflow;
  final String amountLabel;

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${local.day} ${_month(local.month)} · $h12:$m $period';
  }

  String _month(int m) {
    const names = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return names[m];
  }

  @override
  Widget build(BuildContext context) {
    final color = inflow ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final bg = inflow ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              inflow ? '+${amountLabel.replaceAll(' ر.ي', '')}' : '-${amountLabel.replaceAll(' ر.ي', '')}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (tx.reference != null && tx.reference!.isNotEmpty)
                  Text(
                    tx.reference!,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  _fmtTime(tx.createdAt),
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${inflow ? '+' : '-'}$amountLabel',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// ورقة تصفية الأنواع — مجموعات مطابقة للفيديو.
class _TypeFilterSheet extends StatefulWidget {
  const _TypeFilterSheet({required this.initial});
  final Set<TransactionType> initial;

  @override
  State<_TypeFilterSheet> createState() => _TypeFilterSheetState();
}

class _TypeFilterSheetState extends State<_TypeFilterSheet> {
  late Set<TransactionType> _selected;

  static const _groups = <String, List<TransactionType>>{
    'تعديل رصيد وتسوية': [
      TransactionType.deposit,
      TransactionType.settlement,
    ],
    'عمليات صرف الكروت والمكافآت': [
      TransactionType.sale,
      TransactionType.advance,
      TransactionType.reward,
    ],
    'الخصومات والتسويات والإلغاء': [
      TransactionType.withdrawal,
      TransactionType.reversal,
    ],
  };

  static String _label(TransactionType t) => switch (t) {
        TransactionType.deposit => 'تعديل رصيد - إضافة (+)',
        TransactionType.settlement => 'تسوية حساب نقطة بيع',
        TransactionType.sale => 'صرف كرت آلي / يدوي',
        TransactionType.advance => 'صرف كرت سلفني (آجل)',
        TransactionType.reward => 'صرف كرت مكافأة ترويجية',
        TransactionType.withdrawal => 'تعديل رصيد - خصم (-) / خصم يدوي',
        TransactionType.reversal => 'إلغاء مكافأة ترويجية (عكس)',
      };

  @override
  void initState() {
    super.initState();
    _selected = Set<TransactionType>.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تصفية حسب نوع العملية',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selected.length} محدد',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => _selected = TransactionType.values.toSet(),
                      ),
                      child: const Text(
                        'تحديد الكل',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text(
                        'إلغاء التحديد',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final entry in _groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((t) {
                          final on = _selected.contains(t);
                          return FilterChip(
                            selected: on,
                            showCheckmark: false,
                            label: Text(
                              _label(t),
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: on
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                            selectedColor: const Color(0xFF0F766E),
                            backgroundColor: const Color(0xFFF8FAFC),
                            side: BorderSide(
                              color: on
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFE2E8F0),
                            ),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _selected.add(t);
                              } else {
                                _selected.remove(t);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, widget.initial),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(fontFamily: 'Tajawal'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => Navigator.pop(context, _selected),
                          child: const Text(
                            'تطبيق',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateFilterSheet extends StatefulWidget {
  const _DateFilterSheet({this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  @override
  State<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<_DateFilterSheet> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
  }

  Future<void> _pick(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'نطاق التاريخ',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text(
                      'من: ${_fmt(_from)}',
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text(
                      'إلى: ${_fmt(_to)}',
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, {
                      'from': null,
                      'to': null,
                    }),
                    child: const Text(
                      'مسح',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                    ),
                    onPressed: () => Navigator.pop(context, {
                      'from': _from,
                      'to': _to,
                    }),
                    child: const Text(
                      'تطبيق',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
