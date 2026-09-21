import 'package:flutter/material.dart';

import '../../../domain/entities/setting.dart';
import '../../../domain/services/report_pdf_service.dart';
import '../../services/report_pdf_export.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../labels/net_labels.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_indicators.dart';
import '../../widgets/net/net_initial_avatar.dart';
import '../../widgets/net/net_sheet.dart';
import '../../widgets/net/net_surface_card.dart';

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

  /// ورقة «تفاصيل المبيعات حسب الفئات» — تجميع عرض فقط من المبيعات المحمّلة.
  ///
  /// كل بيع يتم بقيمة فئة مطابقة تمامًا، فيكفي التجميع بالقيمة الاسمية
  /// وربطها بأسماء الفئات النشطة — دون أي استعلامات أو منطق جديد.
  Future<void> _showCategoryBreakdown() async {
    final byAmount = <int, ({int count, int minor})>{};
    for (final r in _rows) {
      final key = r.sale.amount.minorUnits;
      final prev = byAmount[key] ?? (count: 0, minor: 0);
      byAmount[key] = (
        count: prev.count + 1,
        minor: prev.minor + r.sale.amount.minorUnits,
      );
    }
    final entries = byAmount.entries.toList()
      ..sort((a, b) => b.value.minor.compareTo(a.value.minor));
    if (!mounted) return;
    await NetSheet.show<void>(
      context,
      builder: (_) => _CategoryBreakdownSheet(
        entries: [for (final e in entries) MapEntry(e.key, e.value)],
        totalMinor: _totalMinor,
      ),
    );
  }


  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final c = AppScope.of(context);
    final network = await c.settings.find(SettingKeys.networkName);
    var name = 'Krotak Pro';
    if (network is Success<AppSetting?>) {
      final setting = network.value;
      if (setting != null) {
        final v = setting.value.trim();
        if (v.isNotEmpty) name = v;
      }
    }

    final (from, to) = _bounds();
    String two(int n) => n.toString().padLeft(2, '0');
    final period =
        '${from.year}-${two(from.month)}-${two(from.day)} → ${to.year}-${two(to.month)}-${two(to.day)}';

    final pdfRows = <PdfTableRow>[
      for (final r in _rows)
        PdfTableRow([
          r.sale.createdAt.toLocal().toString().split('.').first,
          r.customerName,
          (r.sale.amount.minorUnits / 100).toStringAsFixed(2),
          r.sale.id,
        ]),
    ];

    final bytes = await (await ReportPdfService.instance()).buildSalesReport(
      title: 'تقرير المبيعات',
      periodLabel: period,
      networkName: name,
      generatedAt: c.clock.now(),
      rows: pdfRows,
      totalLabel: 'الإجمالي: ${(_totalMinor / 100).toStringAsFixed(2)} ر.ي · ${_rows.length} عملية',
    );
    if (!mounted) return;
    await saveReportPdf(context: context, bytes: bytes, fileStem: 'sales_report');
  }

  Widget _rangeChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = KayanPalette.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : palette.textPrimary,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: palette.primary,
      backgroundColor: palette.surface,
      side: BorderSide(
        color: selected
            ? palette.primary
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      shape: const RoundedRectangleBorder(borderRadius: NetRadii.pillAll),
      onSelected: (_) => onTap(),
    );
  }

  List<NetBarDatum> _topCustomerBars(BuildContext context) {
    final net = context.netColors;
    final totals = <String, int>{};
    for (final row in _rows) {
      totals[row.customerName] =
          (totals[row.customerName] ?? 0) + row.sale.amount.minorUnits;
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(8).toList();
    return [
      for (var i = 0; i < top.length; i++)
        NetBarDatum(
          label: top[i].key,
          value: top[i].value / 100,
          color: i == 0 ? net.success : net.info,
          valueLabel: formatMoneyMinor(top[i].value),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقرير المبيعات التفصيلي'),
          actions: [
            IconButton(
              tooltip: 'تصدير PDF',
              onPressed: _rows.isEmpty ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.md,
                NetSpacing.lg,
                NetSpacing.sm,
              ),
              child: Wrap(
                spacing: NetSpacing.sm,
                runSpacing: NetSpacing.sm,
                children: [
                  _rangeChip(
                    context: context,
                    label: 'اليوم',
                    selected: _range == SalesReportRange.today,
                    onTap: () {
                      setState(() => _range = SalesReportRange.today);
                      _load();
                    },
                  ),
                  _rangeChip(
                    context: context,
                    label: 'الشهر',
                    selected: _range == SalesReportRange.month,
                    onTap: () {
                      setState(() => _range = SalesReportRange.month);
                      _load();
                    },
                  ),
                  _rangeChip(
                    context: context,
                    label: 'فترة مختارة',
                    selected: _range == SalesReportRange.custom,
                    onTap: () => _pickCustom(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: NetSpacing.pageH,
              child: NetSurfaceCard(
                padding: NetSpacing.cardTight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 20,
                          color: palette.primary,
                        ),
                        const SizedBox(width: NetSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إجمالي المبيعات المكتملة',
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 12.5,
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: NetSpacing.xxs),
                              Text(
                                formatMoneyMinor(_totalMinor),
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NetSpacing.sm,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.netColors.availableContainer,
                            borderRadius: BorderRadius.circular(NetRadii.xs),
                          ),
                          child: Text(
                            '${_rows.length} كرت',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: context.netColors.available,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(height: NetSpacing.md),
                      NetHorizontalBars(
                        labelWidth: 88,
                        emptyMessage: 'لا توجد مبيعات لهذه الفترة',
                        data: _topCustomerBars(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── تفاصيل المبيعات حسب الفئات (الفيديو t29s) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.sm,
                NetSpacing.lg,
                0,
              ),
              child: NetSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: NetSpacing.md,
                  vertical: NetSpacing.sm,
                ),
                onTap: _rows.isEmpty ? null : _showCategoryBreakdown,
                child: Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      size: NetSizes.iconSm,
                      color: palette.primary,
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Expanded(
                      child: Text(
                        'تفاصيل المبيعات حسب الفئات',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: NetSizes.iconSm,
                      color: palette.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : _rows.isEmpty
                          ? AsyncEmptyView(
                              message: 'لا توجد مبيعات مسجلة لهذه الفترة',
                              hint: 'جرّب تغيير الفترة أو اختر «فترة مختارة».',
                              icon: Icons.receipt_long_outlined,
                              actionLabel: 'إعادة التحميل',
                              onAction: _load,
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: palette.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  NetSpacing.lg,
                                  NetSpacing.sm,
                                  NetSpacing.lg,
                                  NetSpacing.xxl,
                                ),
                                itemCount: _rows.length,
                                itemBuilder: (_, i) {
                                  final row = _rows[i];
                                  final dt = row.sale.createdAt;
                                  final stamp =
                                      '${arabicShortDate(dt)} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  return NetSurfaceCard(
                                    margin: const EdgeInsets.only(
                                      bottom: NetSpacing.sm,
                                    ),
                                    padding: NetSpacing.cardTight,
                                    child: Row(
                                      children: [
                                        NetInitialAvatar(
                                          name: row.customerName,
                                        ),
                                        const SizedBox(width: NetSpacing.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                row.customerName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily:
                                                      NetTypography.family,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: palette.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(
                                                height: NetSpacing.xxs,
                                              ),
                                              Text(
                                                stamp,
                                                style: TextStyle(
                                                  fontFamily:
                                                      NetTypography.family,
                                                  fontSize: 11.5,
                                                  color: palette.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: NetSpacing.sm),
                                        Text(
                                          formatMoneyMinor(
                                            row.sale.amount.minorUnits,
                                          ),
                                          style: TextStyle(
                                            fontFamily: NetTypography.family,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                      ],
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

/// ورقة تفاصيل المبيعات حسب الفئات — عرض فقط: بحث + شريط نسبة لكل فئة.
///
/// التجميع بالقيمة الاسمية لأن كل بيع يقابل فئة مطابقة تمامًا للمبلغ؛
/// اسم الفئة يُعرض عند تطابق قيمة واحدة مع فئة واحدة فقط.
class _CategoryBreakdownSheet extends StatefulWidget {
  const _CategoryBreakdownSheet({
    required this.entries,
    required this.totalMinor,
  });

  /// faceValue (minorUnits) → (عدد الكروت، مجموع البيع).
  final List<MapEntry<int, ({int count, int minor})>> entries;
  final int totalMinor;

  @override
  State<_CategoryBreakdownSheet> createState() =>
      _CategoryBreakdownSheetState();
}

class _CategoryBreakdownSheetState extends State<_CategoryBreakdownSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final q = _query.trim();
    final visible = q.isEmpty
        ? widget.entries
        : widget.entries
            .where((e) => formatMoneyMinor(e.key).contains(q))
            .toList(growable: false);

    return NetSheet(
      title: 'تفاصيل المبيعات حسب الفئات',
      subtitle: 'توزيع مبيعات الفترة المحددة على فئات الكروت',
      icon: Icons.pie_chart_outline_rounded,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'ابحث عن فئة...',
            prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
            filled: true,
            fillColor: palette.surface,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: NetRadii.smAll,
              borderSide: BorderSide(color: palette.border),
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
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 14,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.lg),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NetSpacing.xxl),
            child: Text(
              'لا نتائج مطابقة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                color: palette.textSecondary,
              ),
            ),
          )
        else
          for (final e in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: NetSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatMoneyMinor(e.key),
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${e.value.count} كرت · ${(widget.totalMinor <= 0 ? 0.0 : e.value.minor / widget.totalMinor * 100).toStringAsFixed(e.value.minor * 100 ~/ (widget.totalMinor == 0 ? 1 : widget.totalMinor) >= 10 ? 0 : 1)}%',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.xs),
                  ClipRRect(
                    borderRadius: NetRadii.pillAll,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: widget.totalMinor <= 0
                            ? 0.0
                            : (e.value.minor / widget.totalMinor)
                                .clamp(0.0, 1.0),
                      ),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: palette.surfaceVariant,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(net.available),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
