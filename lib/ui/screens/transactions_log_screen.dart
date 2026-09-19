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

/// سجل العمليات — مطابقة إطارات الفيديو.
///
/// القائمة + تصفية النوع/التاريخ + ورقة تفاصيل الحركة.
class TransactionsLogScreen extends StatefulWidget {
  const TransactionsLogScreen({super.key});

  @override
  State<TransactionsLogScreen> createState() => _TransactionsLogScreenState();
}

class _TransactionsLogScreenState extends State<TransactionsLogScreen> {
  bool _loading = true;
  String? _error;
  List<Transaction> _all = const [];
  TransactionType? _typeFilter;
  DateTimeRange? _dateRange;

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
    final result = await c.transactions.listRecent(limit: 500);
    if (!mounted) return;
    if (result is Failure<List<Transaction>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    final list = (result as Success<List<Transaction>>).value;
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _loading = false;
      _all = list;
    });
  }

  List<Transaction> get _filtered {
    var list = _all;
    if (_typeFilter != null) {
      list = list.where((t) => t.type == _typeFilter).toList();
    }
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      list = list
          .where((t) =>
              !t.createdAt.isBefore(start) && t.createdAt.isBefore(end))
          .toList();
    }
    return list;
  }

  Future<void> _openTypeSheet() async {
    final palette = KayanPalette.of(context);
    final selected = await showModalBottomSheet<TransactionType?>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  title: const Text('كل الأنواع', style: TextStyle(fontFamily: 'Tajawal')),
                  onTap: () => Navigator.pop(ctx, null),
                ),
                for (final t in TransactionType.values)
                  ListTile(
                    title: Text(
                      transactionTypeLabel(t),
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                    selected: _typeFilter == t,
                    onTap: () => Navigator.pop(ctx, t),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _typeFilter = selected);
  }

  Future<void> _openDateSheet() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dateRange = picked);
  }

  void _openDetail(Transaction tx) {
    NetTransactionDetailSheet.show(context, tx);
  }

  String _fmtMoney(Money m) {
    final major = m.minorUnits / 100.0;
    final s = m.minorUnits % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ${m.currencyCode}';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final filtered = _filtered;

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
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'تصفية الأنواع',
            onPressed: _openTypeSheet,
            icon: Icon(Icons.filter_list_rounded, color: palette.primary),
          ),
          IconButton(
            tooltip: 'نطاق التاريخ',
            onPressed: _openDateSheet,
            icon: Icon(Icons.date_range_rounded, color: palette.primary),
          ),
        ],
      ),
      body: _loading
          ? const AsyncLoadingView(skeleton: true, skeletonCount: 6)
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : filtered.isEmpty
                  ? AsyncEmptyView(
                      message: _all.isEmpty
                          ? 'لا توجد عمليات بعد'
                          : 'لا نتائج للتصفية الحالية',
                      icon: Icons.receipt_long_outlined,
                      actionLabel: _typeFilter != null || _dateRange != null
                          ? 'إلغاء التصفية'
                          : null,
                      onAction: _typeFilter != null || _dateRange != null
                          ? () => setState(() {
                                _typeFilter = null;
                                _dateRange = null;
                              })
                          : null,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: palette.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final tx = filtered[i];
                          final credit = tx.type == TransactionType.deposit ||
                              tx.type == TransactionType.reward;
                          return NetSurfaceCard(
                            onTap: () => _openDetail(tx),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: credit
                                        ? net.successContainer
                                        : net.errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    credit
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: credit ? net.success : net.error,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        transactionTypeLabel(tx.type),
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        [
                                          if (tx.reference != null &&
                                              tx.reference!.isNotEmpty)
                                            tx.reference!,
                                          _fmtTime(tx.createdAt),
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 12,
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${credit ? '+' : '-'}${_fmtMoney(tx.amount)}',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: credit ? net.success : net.error,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
