import 'package:flutter/material.dart';

import '../../../domain/services/report_pdf_service.dart';
import '../../services/report_pdf_export.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/pos_account.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_indicators.dart';
import '../../widgets/net/net_surface_card.dart';

class _PosRow {
  const _PosRow({
    required this.pos,
    required this.account,
    required this.debtMinor,
    required this.prepaidMinor,
  });

  final PointOfSale pos;
  final PosAccount? account;
  final int debtMinor;
  final int prepaidMinor;
}

/// تقرير نقاط البيع: مستحقات الدفتر + عمولة + تسوية يدوية عبر Domain.
class PosReportScreen extends StatefulWidget {
  const PosReportScreen({super.key});

  @override
  State<PosReportScreen> createState() => _PosReportScreenState();
}

class _PosReportScreenState extends State<PosReportScreen> {
  bool _loading = true;
  String? _error;
  List<_PosRow> _items = const [];
  bool _autoSettle = true;

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
    final listed = await c.pointsOfSale.listAll();
    final accounts = await c.posRegistry.listAll();
    final auto = await c.settings.find(SettingKeys.autoPosSettlementEnabled);
    if (!mounted) return;
    if (listed is Failure || accounts is Failure) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل نقاط البيع';
      });
      return;
    }
    final posList = (listed as Success<List<PointOfSale>>).value;
    final accList = (accounts as Success<List<PosAccount>>).value;
    final byPos = {for (final a in accList) a.posId: a};
    final rows = <_PosRow>[];
    for (final pos in posList) {
      final acc = byPos[pos.id];
      var debt = 0;
      var prepaid = 0;
      if (acc != null) {
        final bal = await c.balanceService.getBalance(
          customerId: acc.customerId,
          currencyCode: 'YER',
        );
        if (bal is Success<Money>) {
          final minor = bal.value.minorUnits;
          if (minor < 0) {
            debt = -minor;
          } else {
            prepaid = minor;
          }
        }
      }
      rows.add(_PosRow(
        pos: pos,
        account: acc,
        debtMinor: debt,
        prepaidMinor: prepaid,
      ));
    }
    if (!mounted) return;
    final autoVal = auto is Success<AppSetting?> ? auto.value?.value : null;
    setState(() {
      _loading = false;
      _items = rows;
      _autoSettle = SettingBool.read(
        autoVal,
        defaultValue: true,
      );
    });
  }

  Future<void> _toggleAuto(bool value) async {
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(
        key: SettingKeys.autoPosSettlementEnabled,
        value: value ? 'true' : 'false',
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _autoSettle = value);
  }

  Future<void> _settle(_PosRow row) async {
    final acc = row.account;
    if (acc == null || row.debtMinor <= 0) return;
    final controller = TextEditingController(
      text: (row.debtMinor / 100.0).toStringAsFixed(
        row.debtMinor % 100 == 0 ? 0 : 2,
      ),
    );
    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسوية نقطة بيع', style: TextStyle(fontFamily: 'Tajawal')),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'المبلغ بالريال',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final major = double.tryParse(controller.text.trim());
                if (major == null || major <= 0) return;
                Navigator.pop(ctx, (major * 100).round());
              },
              child: const Text('تسوية'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed == null || !mounted) return;
    final c = AppScope.of(context);
    final result = await c.balanceService.credit(
      customerId: acc.customerId,
      amount: Money(minorUnits: confirmed, currencyCode: 'YER'),
      reference: 'pos-manual-settle:${acc.posId}:${c.ids.next('ref')}',
    );
    if (!mounted) return;
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result as Failure).error.message)),
      );
      return;
    }
    await _load();
  }

  String _commission(PosAccount? acc) {
    if (acc == null) return 'غير مربوط';
    return acc.percentageMode == PosPercentageMode.zero
        ? 'عمولة 0%'
        : 'عمولة الفئة الافتراضية';
  }


  Future<void> _exportPdf() async {
    if (_items.isEmpty) return;
    final c = AppScope.of(context);
    final network = await c.settings.find(SettingKeys.networkName);
    var name = 'Krotak Pro';
    if (network is Success<AppSetting?>) {
      final setting = network.value;
      if (setting != null && setting.value.trim().isNotEmpty) {
        name = setting.value.trim();
      }
    }
    final rows = <PdfTableRow>[
      for (final r in _items)
        PdfTableRow([
          c.clock.now().toLocal().toString().split(' ').first,
          'نقطة بيع',
          r.pos.name,
          (r.debtMinor / 100).toStringAsFixed(2),
          r.pos.status.name,
        ]),
    ];
    final debtTotal = _items.fold<int>(0, (a, e) => a + e.debtMinor);
    final bytes = await (await ReportPdfService.instance()).buildLedgerStatement(
      title: 'تقرير نقاط البيع',
      accountLabel: 'مستحقات نقاط البيع من الدفتر',
      networkName: name,
      generatedAt: c.clock.now(),
      balanceLabel: 'إجمالي الديون: ${(debtTotal / 100).toStringAsFixed(2)} ر.ي · ${_items.length} نقطة',
      rows: rows,
    );
    if (!mounted) return;
    await saveReportPdf(context: context, bytes: bytes, fileStem: 'pos_report');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'تصدير PDF',
              onPressed: _items.isEmpty ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],

          title: const Text(
            'تقرير نقاط البيع',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(NetSpacing.lg),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'التسوية التلقائية للحوالات',
                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'عند التفعيل: حوالة بمعرّف POS تسجّل إيداعاً ولا تبيع كرتاً',
                            style: TextStyle(fontFamily: 'Tajawal'),
                          ),
                          value: _autoSettle,
                          onChanged: _toggleAuto,
                        ),
                        const SizedBox(height: NetSpacing.md),
                        if (_items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: AsyncEmptyView(message: 'لا نقاط بيع مسجّلة'),
                          )
                        else ...[
                          _PosSummaryCard(items: _items),
                          const SizedBox(height: NetSpacing.md),
                          ..._items.map((row) {
                            return NetSurfaceCard(
                              margin: const EdgeInsets.only(bottom: NetSpacing.md),
                              padding: NetSpacing.cardTight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.pos.name,
                                    style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: NetSpacing.xs),
                                  Text(
                                    'الحالة: ${_posStatusLabel(row.pos.status)} · ${_commission(row.account)}',
                                    style: const TextStyle(fontFamily: 'Tajawal'),
                                  ),
                                  if (row.account != null)
                                    Text(
                                      'معرّفات: ${row.account!.identifiers.join('، ')}',
                                      style: const TextStyle(fontFamily: 'Tajawal'),
                                    ),
                                  const SizedBox(height: NetSpacing.sm),
                                  Text(
                                    row.debtMinor > 0
                                        ? 'المستحق: ${formatMoneyMinor(row.debtMinor)}'
                                        : 'رصيد مدفوع مقدماً: ${formatMoneyMinor(row.prepaidMinor)}',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontWeight: FontWeight.w700,
                                      color: row.debtMinor > 0
                                          ? context.netColors.warning
                                          : context.kayan.primary,
                                    ),
                                  ),
                                  if (row.account != null && row.debtMinor > 0)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () => _settle(row),
                                        child: const Text(
                                          'تسوية يدوية',
                                          style: TextStyle(fontFamily: 'Tajawal'),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

String _posStatusLabel(PointOfSaleStatus status) {
  switch (status) {
    case PointOfSaleStatus.active:
      return 'نشط';
    case PointOfSaleStatus.suspended:
      return 'موقوف';
    case PointOfSaleStatus.archived:
      return 'مؤرشف';
  }
}

class _PosSummaryCard extends StatelessWidget {
  const _PosSummaryCard({required this.items});

  final List<_PosRow> items;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final debtTotal = items.fold<int>(0, (a, r) => a + r.debtMinor);
    final prepaidTotal = items.fold<int>(0, (a, r) => a + r.prepaidMinor);
    final linked = items.where((r) => r.account != null).length;
    final ranked = [...items]
      ..sort((a, b) => b.debtMinor.compareTo(a.debtMinor));
    final top = ranked.take(8).toList();
    return NetSurfaceCard(
      padding: NetSpacing.cardTight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NetIndicatorGrid(
            indicators: [
              NetIndicatorTile(
                label: 'نقاط البيع',
                value: '${items.length}',
                icon: Icons.storefront_rounded,
              ),
              NetIndicatorTile(
                label: 'مربوطة',
                value: '$linked',
                icon: Icons.link_rounded,
                tint: net.info,
              ),
              NetIndicatorTile(
                label: 'إجمالي المستحق',
                value: formatMoneyMinor(debtTotal),
                icon: Icons.south_west_rounded,
                tint: net.warning,
              ),
              NetIndicatorTile(
                label: 'مدفوع مقدماً',
                value: formatMoneyMinor(prepaidTotal),
                icon: Icons.north_east_rounded,
                tint: net.success,
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          NetHorizontalBars(
            labelWidth: 88,
            emptyMessage: 'لا مستحقات مسجّلة',
            data: [
              for (final row in top)
                if (row.debtMinor > 0 || row.prepaidMinor > 0)
                  NetBarDatum(
                    label: row.pos.name,
                    value: (row.debtMinor > 0 ? row.debtMinor : row.prepaidMinor) / 100,
                    color: row.debtMinor > 0 ? net.warning : net.success,
                    valueLabel: formatMoneyMinor(
                      row.debtMinor > 0 ? row.debtMinor : row.prepaidMinor,
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
