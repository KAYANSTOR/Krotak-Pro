import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/pos_account.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../widgets/async_views.dart';

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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
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
                      padding: const EdgeInsets.all(16),
                      children: [
                        SwitchListTile(
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
                        const SizedBox(height: 8),
                        if (_items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: AsyncEmptyView(message: 'لا نقاط بيع مسجّلة'),
                          )
                        else
                          ..._items.map((row) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
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
                                    const SizedBox(height: 4),
                                    Text(
                                      'الحالة: ${row.pos.status.name} · ${_commission(row.account)}',
                                      style: const TextStyle(fontFamily: 'Tajawal'),
                                    ),
                                    if (row.account != null)
                                      Text(
                                        'معرّفات: ${row.account!.identifiers.join('، ')}',
                                        style: const TextStyle(fontFamily: 'Tajawal'),
                                      ),
                                    const SizedBox(height: 8),
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
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
      ),
    );
  }
}
