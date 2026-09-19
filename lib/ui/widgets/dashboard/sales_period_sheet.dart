import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../theme/net_tokens.dart';
import '../async_views.dart';
import '../net/net_initial_avatar.dart';
import '../net/net_surface_card.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: NetRadii.sheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: NetSpacing.sm),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: NetRadii.pillAll,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.xxl,
                NetSpacing.lg,
                NetSpacing.xxl,
                NetSpacing.md,
              ),
              child: Text(
                _title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: NetSpacing.xxl),
                child: AsyncLoadingView(skeleton: true, skeletonCount: 5),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NetSpacing.xxl,
                  horizontal: NetSpacing.xxl,
                ),
                child: AsyncErrorView(message: _error!, onRetry: _load),
              )
            else if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: NetSpacing.xxl),
                child: AsyncEmptyView(
                  message: _emptyMessage,
                  hint: 'ستظهر هنا كل عمليات البيع المكتملة خلال الفترة المحددة.',
                  icon: Icons.point_of_sale_rounded,
                  compact: true,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.xl,
                    vertical: NetSpacing.sm,
                  ),
                  itemCount: _rows.length,
                  itemBuilder: (context, i) => _SaleTile(
                    row: _rows[i],
                    timeLabel: _formatTime(_rows[i].sale.createdAt),
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                NetSpacing.xxl,
                NetSpacing.lg,
                NetSpacing.xxl,
                NetSpacing.md + bottom,
              ),
              child: Column(
                children: [
                  NetSurfaceCard(
                    padding: NetSpacing.cardTight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.functions_rounded,
                              size: NetSizes.iconSm,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: NetSpacing.sm),
                            Expanded(
                              child: Text(
                                'إجمالي المبيعات',
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NetSpacing.xs),
                        Text(
                          _totalValueLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: NetRadii.pillAll,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onGoToReport();
                      },
                      icon: const Icon(Icons.bar_chart_rounded, size: 20),
                      label: const Text(
                        'الذهاب إلى تقرير المبيعات التفصيلي',
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NetSpacing.md),
      child: Row(
        children: [
          NetInitialAvatar(name: row.customerName, size: 36),
          const SizedBox(width: NetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: NetSpacing.xxs),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Text(
            formatMoneyMinor(row.sale.amount.minorUnits),
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
