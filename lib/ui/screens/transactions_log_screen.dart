import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../labels/net_labels.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_transaction_detail_sheet.dart';
import '../widgets/net/net_app_bar_title.dart';

/// سجل العمليات — مطابقة إطارات الفيديو (`frame_t500s` / `inv_t480s`).
///
/// - بحث + فلاتر أنواع/تواريخ
/// - ملخص ثابت: عدد · صافي · إيداعات · صرف
/// - بطاقات عملية مجمّعة باليوم مع مبلغ ونوع ووقت
/// - ورقة تصفية حسب نوع العملية (مجموعات الفيديو)
/// - Domain: transactions.listRecent
///
/// التحديث الجديد بصري بالكامل: الثيم والوضع الداكن، تجميع باليوم، هياكل
/// تحميل، وحالات فارغة قابلة للتنفيذ. لا تغيير في الاستعلام أو الحسابات.
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

  int get _netSum => _depositSum - _outflowSum;

  bool _isInflow(TransactionType t) =>
      t == TransactionType.deposit || t == TransactionType.reversal;

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

  Future<void> _openAdvancedOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdvancedOptionsSheet(
        typeCount: _typeFilter.length,
        hasDateRange: _from != null || _to != null,
      ),
    );
    if (choice == 'date') await _openDateSheet();
    if (choice == 'type') await _openTypeSheet();
  }

  static DateTime _dayOf(DateTime timestamp) {
    final local = timestamp.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return Scaffold(
      backgroundColor: palette.appBackground,
      appBar: AppBar(
        backgroundColor: palette.appBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'رجوع',
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary),
        ),
        title: const NetAppBarTitle(
          icon: Icons.receipt_long_rounded,
          title: 'سجل العمليات',
          subtitle: 'عرض وتصفية جميع المعاملات المسجلة',
        ),
        actions: [
          IconButton(
            tooltip: 'تصفية الأنواع',
            onPressed: _openTypeSheet,
            icon: Icon(Icons.filter_list_rounded, color: palette.primary),
          ),
          IconButton(
            tooltip: 'خيارات متقدمة',
            onPressed: _openAdvancedOptions,
            icon: Icon(Icons.tune_rounded, color: palette.primary),
          ),
        ],
      ),
      body: Column(
        children: [
          // بحث
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NetSpacing.lg,
              NetSpacing.sm,
              NetSpacing.lg,
              NetSpacing.sm,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontFamily: NetTypography.family, color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم، رقم الكرت، الحوالة...',
                hintStyle: TextStyle(
                  fontFamily: NetTypography.family,
                  color: palette.textTertiary,
                  fontSize: 13,
                ),
                prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () => setState(_searchCtrl.clear),
                        icon: Icon(Icons.clear_rounded, color: palette.textTertiary),
                      ),
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: NetRadii.mdAll,
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: NetRadii.mdAll,
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: NetRadii.mdAll,
                  borderSide: BorderSide(color: palette.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.md,
                  vertical: NetSpacing.sm,
                ),
              ),
            ),
          ),
          // شرائح الفلاتر
          if (_hasFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                0,
                NetSpacing.lg,
                NetSpacing.sm,
              ),
              child: Wrap(
                spacing: NetSpacing.sm,
                runSpacing: NetSpacing.xs,
                children: [
                  if (_from != null || _to != null)
                    _FilterChip(
                      label: _dateChipLabel(),
                      onDeleted: () => setState(() {
                        _from = null;
                        _to = null;
                      }),
                    ),
                  if (_typeFilter.isNotEmpty)
                    _FilterChip(
                      selected: true,
                      label: _typeFilter.isEmpty
                          ? 'أنواع'
                          : '${_typeFilter.length} أنواع',
                      onDeleted: () => setState(() => _typeFilter.clear()),
                    ),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                    label: const Text('مسح الكل'),
                    style: TextButton.styleFrom(
                      foregroundColor: net.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          // ملخص ثابت أعلى القائمة
          _SummaryBar(
            count: items.length,
            netLabel: _fmtSigned(_netSum.abs(), positive: _netSum >= 0),
            depositLabel: _fmtSigned(_depositSum, positive: true),
            outflowLabel: _fmtSigned(_outflowSum, positive: false),
            netPositive: _netSum >= 0,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? AsyncErrorView(
                        message: _error!,
                        onRetry: _load,
                      )
                    : items.isEmpty
                        ? AsyncEmptyView(
                            title: 'لا توجد عمليات',
                            message: _hasFilters
                                ? 'جرّب توسيع نطاق التاريخ أو مسح الفلاتر'
                                : 'ستظهر هنا كل حركات الإيداع والصرف',
                            actionLabel: _hasFilters ? 'مسح الفلاتر' : null,
                            onAction: _hasFilters ? _clearAll : null,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: _buildGroupedList(items),
                          ),
          ),
        ],
      ),
    );
  }

  String _dateChipLabel() {
    if (_from != null && _to != null) {
      return '${_fmtShort(_from!)} → ${_fmtShort(_to!)}';
    }
    if (_from != null) return 'من ${_fmtShort(_from!)}';
    if (_to != null) return 'حتى ${_fmtShort(_to!)}';
    return 'تاريخ';
  }

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _buildGroupedList(List<Transaction> items) {
    final groups = <DateTime, List<Transaction>>{};
    for (final tx in items) {
      final day = _dayOf(tx.createdAt);
      (groups[day] ??= []).add(tx);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: NetSpacing.xxl),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final txs = groups[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayHeader(day: day, count: txs.length),
            ...txs.map(
              (tx) => _TxCard(
                tx: tx,
                label: _typeLabel(tx.type),
                inflow: _isInflow(tx.type),
                amountLabel: _fmtSigned(
                  tx.amount.minorUnits,
                  positive: _isInflow(tx.type),
                ),
                onTap: () =>
                    NetTransactionDetailSheet.show(context, tx),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.selected = true,
    this.onDeleted,
  });

  final String label;
  final bool selected;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return FilterChip(
      selected: selected,
      label: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      onSelected: (_) {},
      onDeleted: onDeleted,
      deleteIcon: onDeleted == null
          ? null
          : Icon(Icons.close_rounded, size: 16, color: palette.textSecondary),
      selectedColor: palette.primary.withValues(
        alpha: palette.isDark ? 0.22 : 0.12,
      ),
      checkmarkColor: palette.primary,
      side: BorderSide(color: palette.border),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String label;
    if (day == today) {
      label = 'اليوم';
    } else if (day == yesterday) {
      label = 'أمس';
    } else {
      label =
          '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.md,
        NetSpacing.lg,
        NetSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Text(
            '($count)',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              color: palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedOptionsSheet extends StatelessWidget {
  const _AdvancedOptionsSheet({
    required this.typeCount,
    required this.hasDateRange,
  });

  final int typeCount;
  final bool hasDateRange;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: NetRadii.sheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.lg,
          NetSpacing.md,
          NetSpacing.lg,
          NetSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: NetRadii.pillAll,
              ),
            ),
            const SizedBox(height: NetSpacing.md),
            Text(
              'خيارات متقدمة',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.md),
            ListTile(
              leading: Icon(Icons.date_range_rounded, color: palette.primary),
              title: const Text('نطاق التاريخ'),
              subtitle: Text(
                hasDateRange ? 'مفعّل' : 'اختر من / إلى',
                style: TextStyle(fontFamily: NetTypography.family),
              ),
              onTap: () => Navigator.pop(context, 'date'),
            ),
            ListTile(
              leading: Icon(Icons.category_rounded, color: palette.primary),
              title: const Text('نوع العملية'),
              subtitle: Text(
                typeCount == 0 ? 'الكل' : '$typeCount محدد',
                style: TextStyle(fontFamily: NetTypography.family),
              ),
              onTap: () => Navigator.pop(context, 'type'),
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
    required this.netPositive,
  });

  final int count;
  final String netLabel;
  final String depositLabel;
  final String outflowLabel;
  final bool netPositive;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        0,
        NetSpacing.lg,
        NetSpacing.sm,
      ),
      child: NetSurfaceCard(
        padding: const EdgeInsets.symmetric(
          horizontal: NetSpacing.md,
          vertical: NetSpacing.sm,
        ),
        child: Row(
          children: [
            _SumCell(label: 'العدد', value: '$count'),
            _vDiv(palette),
            _SumCell(
              label: 'صافي',
              value: netLabel,
              color: netPositive ? net.available : net.error,
            ),
            _vDiv(palette),
            _SumCell(
              label: 'إجمالي الإيداعات',
              value: depositLabel,
              color: net.available,
            ),
            _vDiv(palette),
            _SumCell(
              label: 'إجمالي الصرف',
              value: outflowLabel,
              color: net.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDiv(KayanPalette palette) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: palette.border,
      );
}

class _SumCell extends StatelessWidget {
  const _SumCell({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 10,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: color ?? palette.textPrimary,
            ),
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
    this.onTap,
  });

  final Transaction tx;
  final String label;
  final bool inflow;
  final String amountLabel;
  final VoidCallback? onTap;

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
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final color = inflow ? net.available : net.error;
    final bg = inflow ? net.availableContainer : net.errorContainer;

    return NetSurfaceCard(
      margin: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        0,
        NetSpacing.lg,
        NetSpacing.sm,
      ),
      padding: const EdgeInsets.all(NetSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: NetRadii.smAll,
            ),
            child: Icon(
              inflow ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: NetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
                if (tx.reference != null && tx.reference!.isNotEmpty)
                  Text(
                    tx.reference!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                Text(
                  _fmtTime(tx.createdAt),
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amountLabel,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeFilterSheet extends StatefulWidget {
  const _TypeFilterSheet({required this.initial});

  final Set<TransactionType> initial;

  @override
  State<_TypeFilterSheet> createState() => _TypeFilterSheetState();
}

class _TypeFilterSheetState extends State<_TypeFilterSheet> {
  late Set<TransactionType> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<TransactionType>.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: NetRadii.sheetTop,
          ),
          child: Column(
            children: [
              const SizedBox(height: NetSpacing.md),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: NetRadii.pillAll,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NetSpacing.lg,
                  NetSpacing.md,
                  NetSpacing.lg,
                  NetSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'تصفية حسب نوع العملية',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NetSpacing.sm,
                          vertical: NetSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(
                            alpha: palette.isDark ? 0.22 : 0.12,
                          ),
                          borderRadius: NetRadii.pillAll,
                        ),
                        child: Text(
                          '${_selected.length} محدد',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: palette.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    NetSpacing.lg,
                    0,
                    NetSpacing.lg,
                    NetSpacing.lg,
                  ),
                  children: [
                    Wrap(
                      spacing: NetSpacing.sm,
                      runSpacing: NetSpacing.sm,
                      children: TransactionType.values.map((t) {
                        final selected = _selected.contains(t);
                        return FilterChip(
                          selected: selected,
                          label: Text(
                            _TransactionsLogScreenState._typeLabel(t),
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selected.add(t);
                              } else {
                                _selected.remove(t);
                              }
                            });
                          },
                          selectedColor: palette.primary.withValues(
                            alpha: palette.isDark ? 0.22 : 0.12,
                          ),
                          checkmarkColor: palette.primary,
                          side: BorderSide(color: palette.border),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NetSpacing.lg,
                    NetSpacing.sm,
                    NetSpacing.lg,
                    NetSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _selected.clear()),
                          child: const Text('مسح'),
                        ),
                      ),
                      const SizedBox(width: NetSpacing.md),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, _selected),
                          child: const Text('تطبيق'),
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

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: NetRadii.sheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.lg,
          NetSpacing.md,
          NetSpacing.lg,
          NetSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: NetRadii.pillAll,
              ),
            ),
            const SizedBox(height: NetSpacing.md),
            Text(
              'نطاق التاريخ',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.lg),
            ListTile(
              leading: Icon(Icons.calendar_today_rounded, color: palette.primary),
              title: const Text('من تاريخ'),
              subtitle: Text(
                _from == null
                    ? 'غير محدد'
                    : '${_from!.day}/${_from!.month}/${_from!.year}',
                style: TextStyle(fontFamily: NetTypography.family),
              ),
              onTap: _pickFrom,
            ),
            ListTile(
              leading: Icon(Icons.event_rounded, color: palette.primary),
              title: const Text('إلى تاريخ'),
              subtitle: Text(
                _to == null
                    ? 'غير محدد'
                    : '${_to!.day}/${_to!.month}/${_to!.year}',
                style: TextStyle(fontFamily: NetTypography.family),
              ),
              onTap: _pickTo,
            ),
            const SizedBox(height: NetSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _from = null;
                      _to = null;
                    }),
                    child: const Text('مسح'),
                  ),
                ),
                const SizedBox(width: NetSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, {
                      'from': _from,
                      'to': _to,
                    }),
                    child: const Text('تطبيق'),
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
