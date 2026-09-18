import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../widgets/async_views.dart';

enum SalesReportRange { today, month, custom }

/// تقرير المبيعات حسب الفترة — مصدر وحيد SaleRepository.listCompletedBetween.
class SalesPeriodReportScreen extends StatefulWidget {
  const SalesPeriodReportScreen({
    super.key,
    this.initialRange = SalesReportRange.today,
  });

  final SalesReportRange initialRange;

  @override
  State<SalesPeriodReportScreen> createState() =>
      _SalesPeriodReportScreenState();
}

class _Row {
  const _Row({required this.sale, required this.customerName});
  final Sale sale;
  final String customerName;
}

class _SalesPeriodReportScreenState extends State<SalesPeriodReportScreen> {
  late SalesReportRange _range;
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _loading = true;
  String? _error;
  List<_Row> _rows = const [];
  int _totalMinor = 0;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  (DateTime from, DateTime to) _bounds() {
    final now = AppScope.of(context).clock.now();
    switch (_range) {
      case SalesReportRange.today:
        return (DateTime(now.year, now.month, now.day), now);
      case SalesReportRange.month:
        return (DateTime(now.year, now.month, 1), now);
      case SalesReportRange.custom:
        final from = _customFrom ?? DateTime(now.year, now.month, 1);
        final to = _customTo ?? now;
        return (from, to.isBefore(from) ? from : to);
    }
  }

  Future<void> _pickCustom() async {
    final now = AppScope.of(context).clock.now();
    final from = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: _customFrom ?? DateTime(now.year, now.month, 1),
    );
    if (!mounted || from == null) return;
    final to = await showDatePicker(
      context: context,
      firstDate: from,
      lastDate: now,
      initialDate: _customTo ?? now,
    );
    if (!mounted || to == null) return;
    setState(() {
      _range = SalesReportRange.custom;
      _customFrom = DateTime(from.year, from.month, from.day);
      _customTo = DateTime(to.year, to.month, to.day, 23, 59, 59);
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final (from, to) = _bounds();
    final salesResult = await c.sales.listCompletedBetween(from, to);
    if (!mounted) return;
    if (salesResult is Failure) {
      setState(() {
        _loading = false;
        _error = (salesResult as Failure).error.message;
      });
      return;
    }
    final sales = List<Sale>.from((salesResult as Success<List<Sale>>).value)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final names = <String, String>{};
    for (final sale in sales) {
      if (names.containsKey(sale.customerId)) continue;
      final cr = await c.customers.findById(sale.customerId);
      if (cr is Success<Customer?> && cr.value != null) {
        final name = cr.value!.displayName.trim();
        names[sale.customerId] = name.isNotEmpty ? name : sale.customerId;
      } else {
        names[sale.customerId] = sale.customerId;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = [
        for (final s in sales)
          _Row(sale: s, customerName: names[s.customerId] ?? s.customerId),
      ];
      _totalMinor = sales.fold(0, (a, s) => a + s.amount.minorUnits);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'تقرير المبيعات التفصيلي',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('اليوم', style: TextStyle(fontFamily: 'Tajawal')),
                    selected: _range == SalesReportRange.today,
                    onSelected: (_) {
                      setState(() => _range = SalesReportRange.today);
                      _load();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('الشهر', style: TextStyle(fontFamily: 'Tajawal')),
                    selected: _range == SalesReportRange.month,
                    onSelected: (_) {
                      setState(() => _range = SalesReportRange.month);
                      _load();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('فترة مختارة', style: TextStyle(fontFamily: 'Tajawal')),
                    selected: _range == SalesReportRange.custom,
                    onSelected: (_) => _pickCustom(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(
                  title: const Text(
                    'إجمالي المبيعات المكتملة',
                    style: TextStyle(fontFamily: 'Tajawal'),
                  ),
                  subtitle: Text(
                    '${formatMoneyMinor(_totalMinor)} · ${_rows.length} كرت',
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : _rows.isEmpty
                          ? const AsyncEmptyView(
                              message: 'لا توجد مبيعات مسجلة لهذه الفترة',
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final row = _rows[i];
                                  final dt = row.sale.createdAt;
                                  final stamp =
                                      '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  return ListTile(
                                    title: Text(
                                      row.customerName,
                                      style: const TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      stamp,
                                      style: const TextStyle(fontFamily: 'Tajawal'),
                                    ),
                                    trailing: Text(
                                      formatMoneyMinor(row.sale.amount.minorUnits),
                                      style: const TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
