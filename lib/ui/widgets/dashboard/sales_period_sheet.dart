import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../async_views.dart';

/// Period for Dashboard sales metric sheets (real SaleRepository data only).
enum SalesPeriod { day, month }

/// Bottom sheet: completed sales for today or current month.
///
/// Visual parity with Kotlin reference (product screenshots):
/// title «تفاصيل مبيعات اليوم/الشهر», empty «لا توجد مبيعات مسجلة لهذه الفترة»,
/// footer «إجمالي المبيعات» + «X ر.ي (N كرت)»,
/// CTA «الذهاب إلى تقرير المبيعات التفصيلي».
class SalesPeriodSheet extends StatefulWidget {
  const SalesPeriodSheet({
    super.key,
    required this.period,
    required this.onGoToReport,
  });

  final SalesPeriod period;
  final VoidCallback onGoToReport;

  static Future<void> show(
    BuildContext context, {
    required SalesPeriod period,
    required VoidCallback onGoToReport,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          SalesPeriodSheet(period: period, onGoToReport: onGoToReport),
    );
  }

  @override
  State<SalesPeriodSheet> createState() => _SalesPeriodSheetState();
}

class _SaleRow {
  const _SaleRow({
    required this.sale,
    required this.customerName,
  });

  final Sale sale;
  final String customerName;
}

class _SalesPeriodSheetState extends State<SalesPeriodSheet> {
  bool _loading = true;
  String? _error;
  List<_SaleRow> _rows = const [];
  int _totalMinor = 0;

  String get _title => widget.period == SalesPeriod.day
      ? 'تفاصيل مبيعات اليوم'
      : 'تفاصيل مبيعات الشهر';

  static const _emptyMessage = 'لا توجد مبيعات مسجلة لهذه الفترة';

  String get _loadingMessage => widget.period == SalesPeriod.day
      ? 'جاري تحميل مبيعات اليوم…'
      : 'جاري تحميل مبيعات الشهر…';

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
    final now = c.clock.now();
    final from = widget.period == SalesPeriod.day
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, 1);

    final salesResult = await c.sales.listCompletedBetween(from, now);
    if (!mounted) return;

    if (salesResult is Failure) {
      setState(() {
        _loading = false;
        _error = (salesResult as Failure).error.message;
      });
      return;
    }

    final sales = (salesResult as Success<List<Sale>>).value;
    final sorted = List<Sale>.from(sales)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final nameByCustomerId = <String, String>{};
    for (final sale in sorted) {
      if (nameByCustomerId.containsKey(sale.customerId)) continue;
      final cr = await c.customers.findById(sale.customerId);
      if (cr is Success<Customer?> && cr.value != null) {
        final name = cr.value!.displayName.trim();
        nameByCustomerId[sale.customerId] =
            name.isNotEmpty ? name : sale.customerId;
      } else {
        nameByCustomerId[sale.customerId] = sale.customerId;
      }
    }

    if (!mounted) return;

    final rows = sorted
        .map(
          (s) => _SaleRow(
            sale: s,
            customerName: nameByCustomerId[s.customerId] ?? s.customerId,
          ),
        )
        .toList(growable: false);

    final total = rows.fold<int>(0, (a, r) => a + r.sale.amount.minorUnits);

    setState(() {
      _loading = false;
      _rows = rows;
      _totalMinor = total;
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (widget.period == SalesPeriod.day) {
      return '$h:$m';
    }
    return '${dt.day}/${dt.month} $h:$m';
  }

  String get _totalValueLabel {
    final money = formatMoneyMinor(_totalMinor);
    return '$money (${_rows.length} كرت)';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                _title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: AsyncLoadingView(message: _loadingMessage),
              )
            else if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: AsyncErrorView(message: _error!, onRetry: _load),
              )
            else if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                child: Text(
                  _emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _SaleTile(
                    row: _rows[i],
                    timeLabel: _formatTime(_rows[i].sale.createdAt),
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 12 + bottom),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إجمالي المبيعات',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _totalValueLabel,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: KayanColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onGoToReport();
                      },
                      icon: const Icon(Icons.bar_chart_rounded, size: 20),
                      label: const Text(
                        'الذهاب إلى تقرير المبيعات التفصيلي',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.row,
    required this.timeLabel,
  });

  final _SaleRow row;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: KayanColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoneyMinor(row.sale.amount.minorUnits),
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
