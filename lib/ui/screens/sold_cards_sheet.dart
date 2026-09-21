import 'package:flutter/material.dart';

import '../../domain/entities/setting.dart';
import '../../domain/services/report_pdf_service.dart';
import '../services/report_pdf_export.dart';
import 'package:flutter/services.dart';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/services/sold_cards_service.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';

/// شاشة/ورقة الكروت المباعة: فلاتر تاريخ/فئة/بحث + تصدير CSV + حذف (tombstone).
Future<void> showSoldCardsSheet({
  required BuildContext context,
  required List<domain.CardCategory> categories,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SoldCardsSheet(
      categories: categories,
      onChanged: onChanged,
    ),
  );
}

class _SoldCardsSheet extends StatefulWidget {
  const _SoldCardsSheet({required this.categories, this.onChanged});
  final List<domain.CardCategory> categories;
  final VoidCallback? onChanged;

  @override
  State<_SoldCardsSheet> createState() => _SoldCardsSheetState();
}

class _SoldCardsSheetState extends State<_SoldCardsSheet> {
  bool _loading = true;
  String? _error;
  List<SoldCardRow> _rows = const [];
  String? _categoryId;
  DateTime? _from;
  DateTime? _to;
  final _serialCtrl = TextEditingController();
  final _customerQueryCtrl = TextEditingController();
  String? _posCustomerId;
  List<({String customerId, String label})> _posOptions = const [];
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _customerQueryCtrl.dispose();
    super.dispose();
  }

  SoldCardsService _service() {
    final c = AppScope.of(context);
    return SoldCardsService(
      cards: c.cards,
      sales: c.sales,
      customers: c.customers,
      categories: c.categories,
      auditLogs: c.auditLogs,
      unitOfWork: c.unitOfWork,
      clock: c.clock,
      ids: c.ids,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final posList = await c.pointsOfSale.listAll();
    final accounts = await c.posRegistry.listAll();
    final opts = <({String customerId, String label})>[];
    if (posList is Success<List<PointOfSale>> &&
        accounts is Success<List<PosAccount>>) {
      final byPos = {for (final a in accounts.value) a.posId: a};
      for (final pos in posList.value) {
        final acc = byPos[pos.id];
        if (acc == null) continue;
        opts.add((customerId: acc.customerId, label: pos.name));
      }
    }
    if (mounted) {
      setState(() => _posOptions = opts);
    }

    final r = await _service().query(
      SoldCardsFilter(
        from: _from,
        to: _to,
        categoryId: _categoryId,
        customerId: _posCustomerId,
        serialQuery: _serialCtrl.text,
      ),
    );
    if (!mounted) return;
    if (r is Failure<List<SoldCardRow>>) {
      setState(() {
        _loading = false;
        _error = r.error.message;
      });
      return;
    }
    var rows = (r as Success<List<SoldCardRow>>).value;
    final cq = _customerQueryCtrl.text.trim().toLowerCase();
    if (cq.isNotEmpty) {
      rows = rows
          .where((e) =>
              (e.customerName ?? '').toLowerCase().contains(cq) ||
              (e.customerPhone ?? '').toLowerCase().contains(cq))
          .toList();
    }
    setState(() {
      _loading = false;
      _rows = rows;
      _selected.removeWhere((id) => !_rows.any((e) => e.card.id == id));
    });
  }

  String _fmtMoney(Money m) {
    final major = m.minorUnits / 100.0;
    return major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
  }

  String _fmtDate(DateTime? d) {
    if (d == null || d.millisecondsSinceEpoch == 0) return '—';
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now.subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => _from = DateTime.utc(d.year, d.month, d.day));
    await _load();
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() => _to = DateTime.utc(d.year, d.month, d.day, 23, 59, 59));
    await _load();
  }


  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final c = AppScope.of(context);
    final network = await c.settings.find(SettingKeys.networkName);
    var name = 'Krotak Pro';
    if (network is Success<AppSetting?>) {
      final setting = network.value;
      if (setting != null && setting.value.trim().isNotEmpty) {
        name = setting.value.trim();
      }
    }
    final filterBits = <String>[];
    if (_categoryId != null) filterBits.add('فئة محددة');
    if (_from != null || _to != null) filterBits.add('نطاق تاريخ');
    if (_serialCtrl.text.trim().isNotEmpty) filterBits.add('بحث سيريال');
    final filterLabel = filterBits.isEmpty ? 'كل الكروت المباعة' : filterBits.join(' · ');

    final pdfRows = <PdfTableRow>[
      for (final r in _rows)
        PdfTableRow([
          r.card.serialNumber,
          r.categoryName,
          r.customerName ?? '—',
          r.customerPhone ?? '—',
          r.sale.id == 'unknown'
              ? '—'
              : r.sale.createdAt.toLocal().toString().split('.').first,
          (r.sale.amount.minorUnits / 100).toStringAsFixed(2),
        ]),
    ];
    final total = _rows.fold<int>(0, (a, e) => a + e.sale.amount.minorUnits);
    final bytes = await (await ReportPdfService.instance()).buildSoldCardsReport(
      title: 'تقرير الكروت المباعة',
      filterLabel: filterLabel,
      networkName: name,
      generatedAt: c.clock.now(),
      rows: pdfRows,
      totalLabel: 'الإجمالي: ${(total / 100).toStringAsFixed(2)} ر.ي · ${_rows.length} كرت',
    );
    if (!mounted) return;
    await saveReportPdf(context: context, bytes: bytes, fileStem: 'sold_cards');
  }

  Future<void> _export() async {
    if (_rows.isEmpty) return;
    final csv = _service().exportCsv(_rows);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم نسخ تقرير الكروت المباعة (CSV) — الصقه في Excel أو ملف',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
  }

  Future<void> _tombstoneSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعطيل الكروت المباعة؟', style: TextStyle(fontFamily: 'Tajawal')),
        content: Text(
          'سيتم تحويل ${_selected.length} كرت مباع إلى حالة «معطّل» (tombstone) '
          'مع الإبقاء على السيريال للأثر التدقيقي. لن يُحذف السجل المالي.',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final c = AppScope.of(context);
    final r = await c.catalogService.deleteCards(cardIds: _selected.toList());
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    _selected.clear();
    widget.onChanged?.call();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تعطيل ${(r as Success<int>).value} كرت مباع',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = MediaQuery.sizeOf(context).height * 0.92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: NetRadii.sheetTop,
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: NetRadii.pillAll,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'الكروت المباعة',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تصدير PDF',
                    onPressed: _rows.isEmpty ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                  IconButton(
                    tooltip: 'تصدير CSV',
                    onPressed: _rows.isEmpty ? null : _export,
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  if (_selected.isNotEmpty)
                    IconButton(
                      tooltip: 'تعطيل المحدد',
                      onPressed: _tombstoneSelected,
                      icon: Icon(Icons.block_rounded, color: scheme.error),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _serialCtrl,
                    decoration: InputDecoration(
                      labelText: 'بحث بالسيريال',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customerQueryCtrl,
                    decoration: InputDecoration(
                      labelText: 'بحث بالعميل / الجوال',
                      prefixIcon: const Icon(Icons.person_search_rounded),
                      border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _categoryId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'الفئة',
                            border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('الكل', style: TextStyle(fontFamily: 'Tajawal'))),
                            ...widget.categories.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name, style: const TextStyle(fontFamily: 'Tajawal')),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _categoryId = v);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_posOptions.isNotEmpty)
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _posCustomerId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'نقطة بيع',
                              border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('كل النقاط', style: TextStyle(fontFamily: 'Tajawal'))),
                              ..._posOptions.map(
                                (o) => DropdownMenuItem(
                                  value: o.customerId,
                                  child: Text(o.label, style: const TextStyle(fontFamily: 'Tajawal'), overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() => _posCustomerId = v);
                              _load();
                            },
                          ),
                        ),
                      if (_posOptions.isNotEmpty) const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _pickFrom,
                        child: Text(
                          _from == null ? 'من تاريخ' : _fmtDate(_from),
                          style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: _pickTo,
                        child: Text(
                          _to == null ? 'إلى تاريخ' : _fmtDate(_to),
                          style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_from != null || _to != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _from = null;
                            _to = null;
                          });
                          _load();
                        },
                        child: const Text('مسح التواريخ', style: TextStyle(fontFamily: 'Tajawal')),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView(message: 'جاري تحميل المباعة…')
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : _rows.isEmpty
                          ? const AsyncEmptyView(
                              message: 'لا توجد كروت مباعة مطابقة',
                              hint: 'غيّر الفلاتر أو ألغِ تاريخ البحث',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final row = _rows[i];
                                final selected = _selected.contains(row.card.id);
                                return InkWell(
                                  onLongPress: () {
                                    setState(() {
                                      if (!_selected.remove(row.card.id)) {
                                        _selected.add(row.card.id);
                                      }
                                    });
                                  },
                                  onTap: () {
                                    if (_selected.isEmpty) return;
                                    setState(() {
                                      if (!_selected.remove(row.card.id)) {
                                        _selected.add(row.card.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? scheme.primaryContainer.withValues(alpha: 0.35)
                                          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      borderRadius: NetRadii.mdAll,
                                      border: Border.all(
                                        color: selected ? scheme.primary : scheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                row.card.serialNumber,
                                                style: TextStyle(
                                                  fontFamily: NetTypography.family,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                  color: scheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${_fmtMoney(row.sale.amount)} ر.ي',
                                              style: TextStyle(
                                                fontFamily: NetTypography.family,
                                                fontWeight: FontWeight.w800,
                                                color: context.netColors.sold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${row.categoryName} · ${_fmtDate(row.sale.createdAt)}',
                                          style: TextStyle(
                                            fontFamily: NetTypography.family,
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                        if ((row.customerName ?? '').isNotEmpty ||
                                            (row.customerPhone ?? '').isNotEmpty)
                                          Text(
                                            [
                                              if ((row.customerName ?? '').isNotEmpty) row.customerName,
                                              if ((row.customerPhone ?? '').isNotEmpty) row.customerPhone,
                                            ].join(' · '),
                                            style: TextStyle(
                                              fontFamily: NetTypography.family,
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${_rows.length} كرت · اضغط مطوّلاً للتحديد · تصدير CSV من الأعلى',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
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
