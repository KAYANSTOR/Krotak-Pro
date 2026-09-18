import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/pos_account.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_initial_avatar.dart';
import '../../widgets/net/net_sheet.dart';
import '../../widgets/net/net_surface_card.dart';

/// حسابات نقاط البيع — مطابقة فيديو المنتج (t74s → t172s):
///
/// - تقرير التسوية المالية حسب الفترة: ملخص (المستحق الصافي / إجمالي المسدد)
/// - بحث باسم/جوال نقطة البيع
/// - كشف حساب لكل نقطة بيع: المستحق الحالي + سقف الدين + آخر التسويات
/// - «تسجيل تسوية مالية»: مبلغ + طريقة دفع + مرجع + ملاحظات → SettlementService
/// - نقطة بيع جديدة / تعديل: جوال + اسم + سقف دين + نسبة (0% أو افتراضية)
///   مع فحص «الرقم مسجل مسبقاً» وشكل الرقم «يبدأ بـ 7 ويتكون من 9 أرقام».
///
/// كل العمليات تمر عبر الخدمات الموجودة (posCatalog / posRegistry /
/// settlementService / balanceService) — لا منطق جديد خارجها.
class PosAccountsLedgerScreen extends StatefulWidget {
  const PosAccountsLedgerScreen({super.key});

  @override
  State<PosAccountsLedgerScreen> createState() =>
      _PosAccountsLedgerScreenState();
}

class _LedgerRow {
  const _LedgerRow({
    required this.pos,
    required this.account,
    required this.customerId,
    required this.debtMinor,
    required this.prepaidMinor,
    this.customerName,
  });

  final PointOfSale pos;
  final PosAccount? account;
  final String customerId;
  final int debtMinor;
  final int prepaidMinor;
  final String? customerName;
}

class _SettlementRow {
  const _SettlementRow({required this.txn, required this.label});
  final Transaction txn;
  final String label;
}

enum _SettleMethod { walletTransfer, bankDeposit, cash }

class _PosAccountsLedgerScreenState extends State<PosAccountsLedgerScreen> {
  bool _loading = true;
  String? _error;
  List<_LedgerRow> _rows = const [];
  final _searchCtrl = TextEditingController();
  String _query = '';

  int get _debtTotal =>
      _rows.fold(0, (a, r) => a + r.debtMinor);
  int get _prepaidTotal =>
      _rows.fold(0, (a, r) => a + r.prepaidMinor);

  List<_LedgerRow> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final name = (r.customerName ?? r.pos.name).toLowerCase();
      if (name.contains(q)) return true;
      final acc = r.account;
      if (acc != null) {
        if ((acc.notifyPhone ?? '').contains(q)) return true;
        if (acc.identifiers.any((i) => i.toLowerCase().contains(q))) return true;
      }
      return false;
    }).toList(growable: false);
  }

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
    final listed = await c.pointsOfSale.listAll();
    final accounts = await c.posRegistry.listAll();
    if (!mounted) return;
    if (listed is Failure || accounts is Failure) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل نقاط البيع';
      });
      return;
    }
    final posList =
        (listed as Success<List<PointOfSale>>).value;
    final accList = (accounts as Success<List<PosAccount>>).value;
    final byPos = {for (final a in accList) a.posId: a};

    final rows = <_LedgerRow>[];
    for (final pos in posList) {
      final acc = byPos[pos.id];
      var debt = 0;
      var prepaid = 0;
      String? customerName;
      if (acc != null) {
        final cr = await c.customers.findById(acc.customerId);
        if (cr is Success<Customer?> && cr.value != null) {
          customerName = cr.value!.displayName;
        }
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
      rows.add(_LedgerRow(
        pos: pos,
        account: acc,
        customerId: acc?.customerId ?? '',
        debtMinor: debt,
        prepaidMinor: prepaid,
        customerName: customerName,
      ));
    }
    rows.sort((a, b) => (b.debtMinor + b.prepaidMinor)
        .compareTo(a.debtMinor + a.prepaidMinor));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  // ── تسجيل تسوية مالية ──────────────────────────────────────────────

  Future<void> _settle(_LedgerRow row) async {
    final acc = row.account;
    if (acc == null) return;
    final done = await NetSheet.show<bool>(
      context,
      builder: (_) => _SettlementSheet(row: row),
    );
    if (done != true || !mounted) return;
    await _load();
  }

  // ── نقطة بيع جديدة / تعديل ─────────────────────────────────────────

  Future<void> _editPos(_LedgerRow? row) async {
    final created = await NetSheet.show<bool>(
      context,
      builder: (_) => _PosFormSheet(existing: row),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final visible = _visible;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'حسابات نقاط البيع',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          onPressed: () => _editPos(null),
          icon: const Icon(Icons.add_business_rounded),
          label: const Text(
            'نقطة بيع جديدة',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    color: palette.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        0, NetSpacing.md, 0, 120,
                      ),
                      children: [
                        // ── ملخص الفترة (بطاقة ذهبية الرأس) ──
                        NetSurfaceCard(
                          margin: NetSpacing.pageH,
                          padding: NetSpacing.card,
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: NetSizes.iconSm,
                                    color: palette.primary,
                                  ),
                                  const SizedBox(width: NetSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'تقرير التسوية المالية لنقاط البيع',
                                      style: TextStyle(
                                        fontFamily: NetTypography.family,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'حالة الحسابات المالية لنقاط البيع المسجّلة',
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 11.5,
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: NetSpacing.md),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SummaryTile(
                                      label: 'المستحق (المديونية)',
                                      value: formatMoneyMinor(_debtTotal),
                                      color: net.error,
                                      background: net.errorContainer,
                                      icon: Icons.south_west_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: NetSpacing.sm),
                                  Expanded(
                                    child: _SummaryTile(
                                      label: 'المدفوع مقدماً',
                                      value: formatMoneyMinor(_prepaidTotal),
                                      color: net.success,
                                      background: net.successContainer,
                                      icon: Icons.north_east_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── البحث ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            NetSpacing.lg,
                            NetSpacing.md,
                            NetSpacing.lg,
                            NetSpacing.sm,
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (v) =>
                                setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText:
                                  'البحث عن نقطة بيع باسمها أو رقم جوالها',
                              hintStyle: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 13,
                                color: palette.textTertiary,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: palette.textTertiary,
                              ),
                              filled: true,
                              fillColor: palette.surface,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: NetRadii.smAll,
                                borderSide:
                                    BorderSide(color: palette.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: NetRadii.smAll,
                                borderSide:
                                    BorderSide(color: palette.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: NetRadii.smAll,
                                borderSide: BorderSide(
                                  color: palette.primary,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),

                        if (visible.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: NetSpacing.xxl),
                            child: AsyncEmptyView(
                              message: _query.isEmpty
                                  ? 'لا نقاط بيع مسجّلة بعد'
                                  : 'لا نتائج لهذا البحث',
                              icon: Icons.storefront_outlined,
                              actionLabel: _query.isEmpty
                                  ? 'إضافة نقطة بيع'
                                  : null,
                              onAction:
                                  _query.isEmpty ? () => _editPos(null) : null,
                            ),
                          )
                        else
                          ...visible.map(
                            (row) => _PosLedgerCard(
                              row: row,
                              onOpen: () => _openLedger(row),
                              onEdit: () => _editPos(row),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── كشف حساب التسويات والمستحقات ───────────────────────────────────

  Future<void> _openLedger(_LedgerRow row) async {
    final acc = row.account;
    if (acc == null) return;
    final c = AppScope.of(context);

    // آخر التسويات: حركات تسوية مكتملة لهذا العميل (قراءة عرض فقط).
    List<_SettlementRow> settlements = const [];
    final txns = await c.transactions.findByCustomer(acc.customerId);
    if (txns is Success<List<Transaction>>) {
      settlements = [
        for (final t in txns.value)
          if (t.type == TransactionType.settlement &&
              t.status == TransactionStatus.completed)
            _SettlementRow(txn: t, label: 'تسوية مالية'),
      ]..sort((a, b) => b.txn.createdAt.compareTo(a.txn.createdAt));
    }

    final bal = await c.balanceService.getBalance(
      customerId: acc.customerId,
      currencyCode: 'YER',
    );
    final balanceMinor =
        bal is Success<Money> ? bal.value.minorUnits : 0;
    if (!mounted) return;

    await NetSheet.show<void>(
      context,
      builder: (_) => _PosLedgerSheet(
        row: row,
        balanceMinor: balanceMinor,
        settlements: settlements.take(8).toList(growable: false),
        onSettle: () => _settle(row),
      ),
    );
  }
}

// ── بطاقة نقطة بيع في القائمة ────────────────────────────────────────

class _PosLedgerCard extends StatelessWidget {
  const _PosLedgerCard({
    required this.row,
    required this.onOpen,
    required this.onEdit,
  });

  final _LedgerRow row;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final name = row.customerName ?? row.pos.name;
    final phone = row.account?.notifyPhone ??
        (row.account?.identifiers.isNotEmpty ?? false
            ? row.account!.identifiers.first
            : null);

    return NetSurfaceCard(
      margin: NetSpacing.pageH,
      padding: const EdgeInsets.all(NetSpacing.md),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NetInitialAvatar(name: name),
              const SizedBox(width: NetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (phone != null) ...[
                      const SizedBox(height: NetSpacing.xxs),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_android_rounded,
                            size: 13,
                            color: palette.textTertiary,
                          ),
                          const SizedBox(width: NetSpacing.xs),
                          Text(
                            phone,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              IconButton(
                tooltip: 'تعديل',
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: row.debtMinor > 0
                      ? 'المستحق الحالي (المديونية)'
                      : 'الرصيد الدائن / الفائض الحالي',
                  value: formatMoneyMinor(
                    row.debtMinor > 0 ? row.debtMinor : -row.prepaidMinor,
                  ),
                  color: row.debtMinor > 0 ? net.error : net.success,
                  background: row.debtMinor > 0
                      ? net.errorContainer
                      : net.successContainer,
                  icon: row.debtMinor > 0
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
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
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NetSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: NetRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: NetSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── كشف حساب التسويات والمستحقات ─────────────────────────────────────

class _PosLedgerSheet extends StatelessWidget {
  const _PosLedgerSheet({
    required this.row,
    required this.balanceMinor,
    required this.settlements,
    required this.onSettle,
  });

  final _LedgerRow row;
  final int balanceMinor;
  final List<_SettlementRow> settlements;
  final VoidCallback onSettle;

  String _fmt(DateTime t) {
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final acc = row.account!;
    final name = row.customerName ?? row.pos.name;

    return NetSheet(
      title: '$name — كشف حساب التسويات والمستحقات',
      subtitle: 'الحالة المالية لنقطة البيع وآخر الحركات المسجّلة',
      icon: Icons.receipt_long_outlined,
      children: [
        _SummaryTile(
          label: balanceMinor < 0
              ? 'المستحق الحالي (المديونية)'
              : 'الرصيد الدائن / الفائض الحالي',
          value: formatMoneyMinor(balanceMinor.abs() * (balanceMinor < 0 ? 1 : -1)),
          color: balanceMinor < 0 ? net.error : net.success,
          background:
              balanceMinor < 0 ? net.errorContainer : net.successContainer,
          icon: balanceMinor < 0
              ? Icons.south_west_rounded
              : Icons.north_east_rounded,
        ),
        const SizedBox(height: NetSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'رقم جوال نقطة البيع',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12,
                  color: palette.textSecondary,
                ),
              ),
            ),
            Text(
              acc.notifyPhone ?? acc.identifiers.firstOrNull ?? '—',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: NetSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                'نسبة نقطة البيع',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12,
                  color: palette.textSecondary,
                ),
              ),
            ),
            Text(
              acc.percentageMode == PosPercentageMode.zero
                  ? '0% (بدون عمولة)'
                  : 'النسبة الافتراضية لفئات الكروت',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: NetSpacing.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onSettle();
          },
          icon: const Icon(Icons.payments_rounded, size: 20),
          label: const Text(
            'تسجيل تسوية مالية',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
        ),
        const SizedBox(height: NetSpacing.lg),
        Text(
          'آخر التسويات المسجّلة',
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.sm),
        if (settlements.isEmpty)
          Text(
            'لا توجد تسويات مسجّلة بعد',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12.5,
              color: palette.textTertiary,
            ),
          )
        else
          ...settlements.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: NetSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: net.success,
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.label} — ${formatMoneyMinor(s.txn.amount.minorUnits)}',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          Text(
                            _fmt(s.txn.createdAt),
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 11.5,
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

// ── تسجيل تسوية مالية ────────────────────────────────────────────────

class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({required this.row});

  final _LedgerRow row;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _collectorCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  _SettleMethod _method = _SettleMethod.walletTransfer;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _collectorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static const _methodLabels = <_SettleMethod, String>{
    _SettleMethod.walletTransfer: 'تحويل محفظة',
    _SettleMethod.bankDeposit: 'إيداع بنكي',
    _SettleMethod.cash: 'نقداً',
  };

  Future<void> _submit() async {
    final major = double.tryParse(_amountCtrl.text.trim());
    if (major == null || major <= 0) {
      setState(() => _status = 'أدخل مبلغاً صحيحاً أكبر من صفر');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final acc = widget.row.account!;
    final ref = _referenceCtrl.text.trim();
    final result = await c.settlementService.settle(
      customerId: acc.customerId,
      amount: Money(
        minorUnits: (major * 100).round(),
        currencyCode: 'YER',
      ),
      reference: ref.isEmpty ? null : 'manual-settle:$ref',
    );
    if (!mounted) return;
    if (result is Failure<Transaction>) {
      setState(() {
        _busy = false;
        _status = (result as Failure).error.message;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final debt = widget.row.debtMinor;

    return NetSheet(
      title: 'تسجيل تسوية مالية',
      subtitle:
          'تسجيل دفعة مسددة من نقطة البيع «${widget.row.customerName ?? widget.row.pos.name}»',
      icon: Icons.payments_rounded,
      children: [
        _SummaryTile(
          label: 'المستحق الحالي (المديونية)',
          value: formatMoneyMinor(debt),
          color: net.error,
          background: net.errorContainer,
          icon: Icons.south_west_rounded,
        ),
        const SizedBox(height: NetSpacing.md),
        TextField(
          controller: _amountCtrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
          ],
          decoration: InputDecoration(
            labelText: 'المبلغ المسدد (ريال) *',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        Text(
          'طريقة الدفع',
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.xs),
        Wrap(
          spacing: NetSpacing.sm,
          children: [
            for (final m in _SettleMethod.values)
              ChoiceChip(
                label: Text(
                  _methodLabels[m]!,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _method == m
                        ? Colors.white
                        : palette.textPrimary,
                  ),
                ),
                selected: _method == m,
                showCheckmark: false,
                selectedColor: palette.primary,
                backgroundColor: palette.surface,
                side: BorderSide(
                  color:
                      _method == m ? palette.primary : palette.border,
                ),
                onSelected: (_) => setState(() => _method = m),
              ),
          ],
        ),
        const SizedBox(height: NetSpacing.md),
        TextField(
          controller: _referenceCtrl,
          decoration: InputDecoration(
            labelText: 'رقم المرجع / الحوالة (اختياري)',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        TextField(
          controller: _collectorCtrl,
          decoration: InputDecoration(
            labelText: 'اسم المحصل / الموظف (اختياري)',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        if (debt <= 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: NetSizes.iconSm,
                color: net.warning,
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  'لا يوجد مستحق حالي — سيتم تسجيل المبلغ كدفعة مقدمة تزيد رصيد نقطة البيع.',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12,
                    color: net.warning,
                  ),
                ),
              ),
            ],
          ),
        if (_status != null) ...[
          const SizedBox(height: NetSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: NetSizes.iconSm,
                color: net.rejected,
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: net.rejected,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: NetSpacing.lg),
        Row(
          children: [
            TextButton(
              onPressed:
                  _busy ? null : () => Navigator.of(context).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontWeight: FontWeight.w700,
                  color: palette.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: NetSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: const Text(
                  'تأكيد التسوية',
                  style: TextStyle(fontFamily: NetTypography.family),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── نقطة بيع جديدة / تعديل ───────────────────────────────────────────

class _PosFormSheet extends StatefulWidget {
  const _PosFormSheet({this.existing});

  final _LedgerRow? existing;

  @override
  State<_PosFormSheet> createState() => _PosFormSheetState();
}

class _PosFormSheetState extends State<_PosFormSheet> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _limitCtrl;
  PosPercentageMode _mode = PosPercentageMode.defaultCategory;
  bool _busy = false;
  String? _status;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final acc = widget.existing?.account;
    _phoneCtrl = TextEditingController(
      text: acc?.notifyPhone ?? acc?.identifiers.firstOrNull ?? '',
    );
    _nameCtrl =
        TextEditingController(text: widget.existing?.pos.name ?? '');
    _limitCtrl = TextEditingController(text: '50000');
    _mode = acc?.percentageMode ?? PosPercentageMode.defaultCategory;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (!RegExp(r'^7\d{8}$').hasMatch(phone)) {
      setState(() => _status = 'الرقم يجب أن يبدأ بـ 7 ويتكون من 9 أرقام');
      return;
    }
    if (name.isEmpty) {
      setState(() => _status = 'أدخل اسم نقطة البيع');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);

    // فحص «الرقم مسجل مسبقاً» عبر هوية العملاء (نفس قاعدة الدفتر).
    final existingById = await c.customers.findByIdentifier(phone);
    if (existingById is Failure<Customer?>) {
      setState(() {
        _busy = false;
        _status = (existingById as Failure).error.message;
      });
      return;
    }
    final existingCustomer =
        (existingById as Success<Customer?>).value;

    if (_isEdit) {
      final row = widget.existing!;
      final acc = row.account!;
      final isSamePhone = acc.notifyPhone == phone ||
          acc.identifiers.contains(phone);
      if (existingCustomer != null &&
          existingCustomer.id != acc.customerId &&
          !isSamePhone) {
        setState(() {
          _busy = false;
          _status = 'رقم الجوال "$phone" مسجل مسبقاً لحساب آخر';
        });
        return;
      }
      final r = await c.posCatalog.updatePointOfSale(
        id: row.pos.id,
        name: name,
        status: row.pos.status,
      );
      if (r is Failure<PointOfSale>) {
        setState(() {
          _busy = false;
          _status = 'تعذر حفظ التعديلات';
        });
        return;
      }
      await c.posRegistry.save(
        acc.copyWith(
          name: name,
          notifyPhone: phone,
          clearNotifyPhone: false,
          percentageMode: _mode,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    // إنشاء جديد
    if (existingCustomer != null) {
      setState(() {
        _busy = false;
        _status = 'رقم الجوال "$phone" مسجل مسبقاً';
      });
      return;
    }
    final create = await c.customerService.create(
      displayName: name,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    if (create is Failure<Customer>) {
      setState(() {
        _busy = false;
        _status = (create as Failure).error.message;
      });
      return;
    }
    final customer = (create as Success<Customer>).value;
    final pos = await c.posCatalog.savePointOfSale(name: name);
    if (pos is Failure<PointOfSale>) {
      setState(() {
        _busy = false;
        _status = 'تعذر إنشاء نقطة البيع';
      });
      return;
    }
    await c.posRegistry.save(
      PosAccount(
        posId: (pos as Success<PointOfSale>).value.id,
        customerId: customer.id,
        name: name,
        identifiers: [phone],
        notifyPhone: phone,
        percentageMode: _mode,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return NetSheet(
      title: _isEdit ? 'تعديل نقطة البيع' : 'نقطة بيع جديدة',
      subtitle: 'بيانات نقطة البيع وحسابها المالي في الدفتر',
      icon: Icons.storefront_outlined,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 9,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'رقم جوال نقطة البيع',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            counterText: '',
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'إسم نقطة البيع',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        TextField(
          controller: _limitCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'سقف الدين المسموح به (ريال) *',
            labelStyle: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textSecondary,
            ),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: NetRadii.mdAll,
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.lg),
        Text(
          'نسبة نقطة البيع',
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.xs),
        Column(
          children: [
            RadioListTile<PosPercentageMode>(
              value: PosPercentageMode.defaultCategory,
              groupValue: _mode,
              onChanged: (v) =>
                  setState(() => _mode = v ?? _mode),
              title: Text(
                'النسبة الافتراضية لفئات الكروت',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13.5,
                  color: palette.textPrimary,
                ),
              ),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile<PosPercentageMode>(
              value: PosPercentageMode.zero,
              groupValue: _mode,
              onChanged: (v) =>
                  setState(() => _mode = v ?? _mode),
              title: Text(
                '0% — بدون عمولة',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13.5,
                  color: palette.textPrimary,
                ),
              ),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: NetSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: NetSizes.iconSm,
                color: net.rejected,
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: net.rejected,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: NetSpacing.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_rounded, size: 20),
          label: Text(
            _isEdit ? 'حفظ التعديلات' : 'إنشاء نقطة البيع',
            style: const TextStyle(fontFamily: NetTypography.family),
          ),
        ),
      ],
    );
  }
}
