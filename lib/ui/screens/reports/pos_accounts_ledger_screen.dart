import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/pos_account.dart';
import '../../../domain/entities/pos_profile.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../routing/app_routes.dart';
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
/// - لا توجد هنا عمليات CRUD لنقطة البيع؛ الإدارة تتم حصراً من الإعدادات.
/// - يتم تحويل المستخدم إلى شاشة إدارة نقطة البيع عند الحاجة.
///
/// القراءة الموحدة تمر عبر `posProfiles`، بينما التسويات المالية تمر عبر
/// `settlementService`.
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
  PointOfSaleStatus? _statusFilter;

  int get _debtTotal =>
      _rows.fold(0, (a, r) => a + r.debtMinor);
  int get _prepaidTotal =>
      _rows.fold(0, (a, r) => a + r.prepaidMinor);

  List<_LedgerRow> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (_statusFilter != null && r.pos.status != _statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;

      final name = (r.customerName ?? r.pos.name).toLowerCase();
      if (name.contains(q)) return true;

      final acc = r.account;
      if (acc != null) {
        if ((acc.notifyPhone ?? '').contains(q)) return true;
        if (acc.identifiers.any((i) => i.toLowerCase().contains(q))) {
          return true;
        }
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

    final profiles = await AppScope.of(context).posProfiles.listPointOfSaleProfiles(
      includeArchived: true,
    );
    if (!mounted) return;

    if (profiles is Failure) {
      setState(() {
        _loading = false;
        _error = (profiles as Failure).error.message;
      });
      return;
    }

    final rows = <_LedgerRow>[];
    for (final profile
        in (profiles as Success<List<PointOfSaleProfile>>).value) {
      final pos = profile.pointOfSale;
      final account = profile.account;
      rows.add(
        _LedgerRow(
          pos: pos,
          account: account,
          customerId: account?.customerId ?? '',
          debtMinor: profile.debtMinorUnits,
          prepaidMinor: profile.prepaidMinorUnits,
          customerName: profile.customer?.displayName,
        ),
      );
    }

    rows.sort(
      (a, b) => (b.debtMinor + b.prepaidMinor).compareTo(
        a.debtMinor + a.prepaidMinor,
      ),
    );

    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  // ── تسجيل تسوية مالية ──────────────────────────────────────────────

  Future<void> _settle(_LedgerRow row) async {
    final acc = row.account;
    if (acc == null || row.pos.status == PointOfSaleStatus.archived) return;
    final done = await NetSheet.show<bool>(
      context,
      builder: (_) => _SettlementSheet(row: row),
    );
    if (done != true || !mounted) return;
    await _load();
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
          actions: [
            IconButton(
              tooltip: 'إدارة نقاط البيع',
              onPressed: () => AppRoutes.openWalletsAndPos(context),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
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
                              const SizedBox(height: NetSpacing.xs),
                              Text(
                                _statusSummary(),
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textTertiary,
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

                        Wrap(
                          spacing: NetSpacing.xs,
                          runSpacing: NetSpacing.xs,
                          children: [
                            for (final filter in <(String, PointOfSaleStatus?)>[
                              ('الكل', null),
                              ('نشطة', PointOfSaleStatus.active),
                              ('موقوفة', PointOfSaleStatus.suspended),
                              ('مؤرشفة', PointOfSaleStatus.archived),
                            ])
                              ChoiceChip(
                                label: Text(
                                  filter.$1,
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                selected: _statusFilter == filter.$2,
                                onSelected: (_) => setState(
                                  () => _statusFilter = filter.$2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: NetSpacing.sm),
                        if (visible.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: NetSpacing.xxl),
                            child: AsyncEmptyView(
                              message: _query.isEmpty
                                  ? 'لا نقاط بيع مطابقة للفلتر'
                                  : 'لا نتائج لهذا البحث',
                              icon: Icons.storefront_outlined,
                              actionLabel: 'إدارة نقاط البيع',
                              onAction: () =>
                                  AppRoutes.openWalletsAndPos(context),
                            ),
                          )
                        else
                          ...visible.map(
                            (row) => _PosLedgerCard(
                              row: row,
                              onOpen: () => _openLedger(row),
                              onManage: () => AppRoutes.openWalletsAndPos(
                                context,
                                focusPosId: row.pos.id,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  String _statusSummary() {
    final active = _rows.where(
      (r) => r.pos.status == PointOfSaleStatus.active,
    ).length;
    final suspended = _rows.where(
      (r) => r.pos.status == PointOfSaleStatus.suspended,
    ).length;
    final archived = _rows.where(
      (r) => r.pos.status == PointOfSaleStatus.archived,
    ).length;
    final incomplete = _rows.where((r) => r.account == null).length;

    return '$active نشطة · $suspended موقوفة · $archived مؤرشفة'
        ' · $incomplete غير مكتملة';
  }

  // ── كشف حساب التسويات والمستحقات ───────────────────────────────────

  Future<void> _openLedger(_LedgerRow row) async {
    final acc = row.account;
    if (acc == null) {
      await AppRoutes.openWalletsAndPos(
        context,
        focusPosId: row.pos.id,
      );
      if (mounted) await _load();
      return;
    }
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
    required this.onManage,
  });

  final _LedgerRow row;
  final VoidCallback onOpen;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final name = row.customerName ?? row.pos.name;
    final phone = row.account?.notifyPhone ??
        (row.account?.identifiers.isNotEmpty ?? false
            ? row.account!.identifiers.first
            : null);
    final archived = row.pos.status == PointOfSaleStatus.archived;
    final incomplete = row.account == null;

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
                tooltip: 'إدارة نقطة البيع',
                onPressed: onManage,
                icon: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Wrap(
            spacing: NetSpacing.xs,
            runSpacing: NetSpacing.xs,
            children: [
              Chip(
                label: Text(
                  _statusLabel(row.pos.status),
                  style: const TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
              if (incomplete)
                Chip(
                  label: const Text(
                    'بيانات الحساب غير مكتملة',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
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
          if (archived) ...[
            const SizedBox(height: NetSpacing.xs),
            Text(
              'الحالة مؤرشفة — التسويات والمعالجة الآلية متوقفة.',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: net.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(PointOfSaleStatus status) {
  switch (status) {
    case PointOfSaleStatus.active:
      return 'نشطة';
    case PointOfSaleStatus.suspended:
      return 'موقوفة';
    case PointOfSaleStatus.archived:
      return 'مؤرشفة';
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
        if (row.pos.status != PointOfSaleStatus.archived)
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
          )
        else
          Text(
            'هذه النقطة مؤرشفة، لذلك لا يمكن تسجيل تسوية جديدة أو تشغيل معالجة مالية آلية.',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: net.warning,
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

