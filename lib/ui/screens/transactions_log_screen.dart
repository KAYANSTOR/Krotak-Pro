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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سجل العمليات',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            Text(
              'عرض وتصفية جميع المعاملات المسجلة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ],
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
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(_searchCtrl.clear),
                      ),
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: NetRadii.smAll,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: NetRadii.smAll,
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: NetRadii.smAll,
                  borderSide: BorderSide(color: palette.primary, width: 1.4),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.md,
                  vertical: NetSpacing.md,
                ),
              ),
            ),
          ),

          // شرائح الفلاتر
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: NetSpacing.pageH,
              children: [
                if (_hasFilters)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: NetSpacing.sm),
                    child: ActionChip(
                      avatar: const Icon(Icons.close_rounded, size: 15),
                      label: const Text(
                        'مسح الكل',
                        style: TextStyle(fontFamily: NetTypography.family, fontSize: 12),
                      ),
                      onPressed: _clearAll,
                    ),
                  ),
                _FilterPill(
                  selected: _typeFilter.isNotEmpty,
                  label: _typeFilter.isEmpty
                      ? 'كل الأنواع'
                      : '${_typeFilter.length} أنواع',
                  icon: Icons.category_rounded,
                  onTap: _openTypeSheet,
                ),
                _FilterPill(
                  selected: _from != null || _to != null,
                  label: (_from == null && _to == null)
                      ? 'كل التواريخ'
                      : 'تواريخ محددة',
                  icon: Icons.calendar_today_rounded,
                  onTap: _openDateSheet,
                ),
              ],
            ),
          ),

          // ملخص ثابت أعلى القائمة
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.sm,
                NetSpacing.lg,
                NetSpacing.sm,
              ),
              child: _SummaryBar(
                count: items.length,
                netLabel: _fmtSigned(_net.abs(), positive: _net >= 0),
                depositLabel: _fmtSigned(_depositSum, positive: true),
                outflowLabel: _fmtSigned(_outflowSum, positive: false),
              ),
            ),

          Expanded(
            child: _loading
                ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
                : _error != null
                    ? AsyncErrorView(message: _error!, onRetry: _load)
                    : items.isEmpty
                        ? AsyncEmptyView(
                            message: 'لا عمليات في الفترة/التصفية المحددة',
                            icon: Icons.receipt_long_outlined,
                            hint: _hasFilters
                                ? 'جرّب توسيع نطاق التاريخ أو مسح الفلاتر'
                                : 'ستظهر هنا كل حركات الإيداع والصرف',
                            actionLabel: _hasFilters ? 'مسح الفلاتر' : null,
                            onAction: _hasFilters ? _clearAll : null,
                          )
                        : RefreshIndicator(
                            color: palette.primary,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: NetSpacing.xxl),
                              itemCount: items.length,
                              itemBuilder: (_, i) {
                                final tx = items[i];
                                final day = _dayOf(tx.createdAt);
                                final isFirstOfDay = i == 0 ||
                                    _dayOf(items[i - 1].createdAt) != day;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (isFirstOfDay)
                                      _DayHeader(label: arabicDayLabel(day)),
                                    _TxCard(
                                      tx: tx,
                                      label: _typeLabel(tx.type),
                                      inflow: _isInflow(tx.type),
                                      amountLabel: _fmtMinor(tx.amount.minorUnits),
                                      onTap: () =>
                                          NetTransactionDetailSheet.show(context, tx),
                                    ),
                                  ],
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NetSpacing.sm),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 14,
          color: selected ? Colors.white : palette.textSecondary,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : palette.textPrimary,
          ),
        ),
        selectedColor: palette.primary,
        backgroundColor: palette.surface,
        side: BorderSide(color: selected ? palette.primary : palette.border),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.xl,
        NetSpacing.md,
        NetSpacing.xl,
        NetSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded, size: 13, color: palette.textSecondary),
          const SizedBox(width: NetSpacing.sm),
          Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(child: Divider(height: 1, color: palette.border)),
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
          NetSpacing.xxl,
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
            const SizedBox(height: NetSpacing.lg),
            Text(
              'خيارات التصفية المتقدمة',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.sm),
            ListTile(
              leading: Icon(Icons.calendar_month_rounded, color: palette.primary),
              title: const Text('نطاق التاريخ'),
              subtitle: Text(
                hasDateRange ? 'نطاق محدد حاليًا' : 'اختر تاريخ البداية والنهاية',
              ),
              onTap: () => Navigator.pop(context, 'date'),
            ),
            ListTile(
              leading: Icon(Icons.category_rounded, color: palette.primary),
              title: const Text('نوع العملية'),
              subtitle: Text(
                typeCount == 0 ? 'كل الأنواع' : '$typeCount أنواع محددة',
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
  });

  final int count;
  final String netLabel;
  final String depositLabel;
  final String outflowLabel;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final isPositive = netLabel.startsWith('+');

    return NetSurfaceCard(
      padding: NetSpacing.cardTight,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.sm,
                  vertical: NetSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: NetRadii.xsAll,
                ),
                child: Text(
                  '$count عملية',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'الصافي: $netLabel',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: isPositive ? net.available : net.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  icon: Icons.arrow_downward_rounded,
                  label: 'إجمالي الإيداعات',
                  value: depositLabel,
                  color: net.available,
                  background: net.availableContainer,
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: _SummaryTile(
                  icon: Icons.arrow_upward_rounded,
                  label: 'إجمالي الصرف / الخصم',
                  value: outflowLabel,
                  color: net.error,
                  background: net.errorContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NetSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: NetRadii.xsAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: NetSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.xxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: palette.textTertiary),
                    const SizedBox(width: NetSpacing.xs),
                    Text(
                      _fmtTime(tx.createdAt),
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11,
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NetSpacing.sm,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: NetRadii.pillAll,
                      ),
                      child: Text(
                        transactionStatusLabel(tx.status),
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Text(
            '${inflow ? '+' : '-'}$amountLabel',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
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
              Padding(
                padding: NetSpacing.pageH,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => _selected = TransactionType.values.toSet(),
                      ),
                      child: const Text('تحديد الكل'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('إلغاء التحديد'),
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
                    for (final entry in _groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: NetSpacing.md,
                          bottom: NetSpacing.sm,
                        ),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: NetSpacing.sm,
                        runSpacing: NetSpacing.sm,
                        children: entry.value.map((t) {
                          final on = _selected.contains(t);
                          return FilterChip(
                            selected: on,
                            showCheckmark: false,
                            label: Text(
                              _label(t),
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: on ? Colors.white : palette.textPrimary,
                              ),
                            ),
                            selectedColor: palette.primary,
                            backgroundColor: palette.surfaceVariant,
                            side: BorderSide(
                              color: on ? palette.primary : palette.border,
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
                  padding: const EdgeInsets.fromLTRB(
                    NetSpacing.lg,
                    0,
                    NetSpacing.lg,
                    NetSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, widget.initial),
                          child: const Text('إلغاء'),
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
          NetSpacing.xxl,
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
            const SizedBox(height: NetSpacing.lg),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text('من: ${_fmt(_from)}'),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text('إلى: ${_fmt(_to)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NetSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, {
                      'from': null,
                      'to': null,
                    }),
                    child: const Text('مسح'),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
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
