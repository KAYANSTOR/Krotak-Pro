import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/dashboard/customer_create_sheet.dart';
import '../widgets/net/net_indicators.dart';
import '../widgets/net/net_initial_avatar.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_tab_header.dart';

enum _AccountFilter { all, debtor, creditor, unlinked }

/// الحسابات والدفتر — مطابق لفيديو Z Net (فلاتر + بطاقات + رقم بديل).
///
/// كل عمليات القراءة والإنشاء كما هي؛ التحديث بصري فقط.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.refreshSignal});

  /// Bumped by the shell when a customer is created elsewhere (quick actions,
  /// dashboard) so this kept-alive tab reloads without reopening it.
  final ValueListenable<int>? refreshSignal;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<_AccountRow> _allRows = const [];
  _AccountFilter _filter = _AccountFilter.all;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _load(_searchCtrl.text);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onExternalRefresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_AccountRow> get _visible {
    switch (_filter) {
      case _AccountFilter.all:
        return _allRows;
      case _AccountFilter.debtor:
        return _allRows.where((r) => (r.balance?.minorUnits ?? 0) < 0).toList();
      case _AccountFilter.creditor:
        return _allRows.where((r) => (r.balance?.minorUnits ?? 0) > 0).toList();
      case _AccountFilter.unlinked:
        return _allRows.where((r) => !r.hasPhone).toList();
    }
  }

  Future<void> _load([String query = '']) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.customers.search(query);
    if (!mounted) return;
    if (result is Failure<List<Customer>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
        _allRows = const [];
      });
      return;
    }
    final customers = (result as Success<List<Customer>>).value
        .where((e) => e.status != CustomerStatus.merged)
        .toList(growable: false);

    final rows = <_AccountRow>[];
    for (final customer in customers) {
      Money? balance;
      final bal = await c.balanceService.getBalance(
        customerId: customer.id,
        currencyCode: 'YER',
      );
      if (bal is Success<Money>) balance = bal.value;

      String? phone;
      String? altId;
      String? altLabel;
      final ids = await c.customers.listIdentifiers(customer.id);
      if (ids is Success<List<CustomerIdentifier>>) {
        final list = ids.value;
        final phones =
            list.where((i) => i.type == CustomerIdentifierType.phoneNumber).toList();
        if (phones.isNotEmpty) {
          phone = phones.firstWhere((i) => i.isPrimary, orElse: () => phones.first).value;
        }
        final external = list
            .where((i) => i.type == CustomerIdentifierType.externalReference)
            .toList();
        if (external.isNotEmpty) {
          altId = external.first.value;
          altLabel = 'الرقم البديل';
        } else if (phone == null) {
          final other = list.where((i) => i.type != CustomerIdentifierType.phoneNumber);
          if (other.isNotEmpty) {
            altId = other.first.value;
            altLabel = other.first.type == CustomerIdentifierType.username
                ? 'اسم المرسل'
                : 'الرقم البديل';
          }
        }
      }

      rows.add(
        _AccountRow(
          customer: customer,
          balance: balance,
          phone: phone,
          altId: altId,
          altLabel: altLabel,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _allRows = rows;
    });
  }

  Future<void> _showCreateSheet() async {
    final created = await CustomerCreateSheet.show(context);
    if (created != null) await _load(_searchCtrl.text);
  }

  void _showAlertsInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تنبيهات الحسابات مرتبطة بتنبيه الرسائل المعلّقة',
          style: TextStyle(fontFamily: NetTypography.family),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// مؤشرات + رسم بياني أفقي لأعلى الأرصدة (عرض فقط، من الصفوف المحمّلة).
  Future<void> _showDistributionSheet() async {
    final rows = _allRows
        .where((r) => (r.balance?.minorUnits ?? 0) != 0)
        .toList(growable: false)
      ..sort(
        (a, b) => (b.balance?.minorUnits ?? 0)
            .abs()
            .compareTo((a.balance?.minorUnits ?? 0).abs()),
      );
    await NetSheet.show<void>(
      context,
      builder: (_) => _BalancesDistributionSheet(
        rows: rows.take(8).toList(growable: false),
        accountsCount: _allRows.length,
        debtorTotalMinor: _debtorTotalMinor,
        creditorTotalMinor: _creditorTotalMinor,
        unlinkedCount: _allRows.where((r) => !r.hasPhone).length,
      ),
    );
  }

  /// Display-only aggregates over the already-loaded rows (no extra queries).
  int get _debtorTotalMinor => _allRows
      .map((r) => r.balance?.minorUnits ?? 0)
      .where((v) => v < 0)
      .fold<int>(0, (a, b) => a + b.abs());
  int get _creditorTotalMinor => _allRows
      .map((r) => r.balance?.minorUnits ?? 0)
      .where((v) => v > 0)
      .fold<int>(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetTabHeader(
          title: 'الحسابات والدفتر',
          subtitle: 'اضغط على أي حساب لعرض التفاصيل وتعديل البيانات.',
          icon: Icons.groups_rounded,
          actions: [
            NetHeaderAction(
              icon: Icons.person_add_alt_1_rounded,
              tooltip: 'إضافة حساب',
              onPressed: _showCreateSheet,
            ),
            NetHeaderAction(
              icon: Icons.volume_up_outlined,
              tooltip: 'تنبيهات الحسابات',
              onPressed: _showAlertsInfo,
            ),
          ],
        ),

        // ── مؤشرات الأرصدة (من البيانات المحمّلة، بلا استعلامات إضافية) ──
        Padding(
          padding: NetSpacing.pageH,
          child: NetSurfaceCard(
            padding: NetSpacing.cardTight,
            onTap: _showDistributionSheet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NetIndicatorGrid(
                  indicators: [
                    NetIndicatorTile(
                      label: 'الحسابات',
                      value: '${_allRows.length}',
                      icon: Icons.groups_rounded,
                    ),
                    NetIndicatorTile(
                      label: 'غير مربوط',
                      value: '${_allRows.where((r) => !r.hasPhone).length}',
                      icon: Icons.link_off_rounded,
                      tint: net.warning,
                    ),
                    NetIndicatorTile(
                      label: 'دفتر مؤقت',
                      value: '${_allRows.where((r) => r.isProvisional).length}',
                      icon: Icons.account_balance_wallet_outlined,
                      tint: net.warning,
                    ),
                    NetIndicatorTile(
                      label: 'إجمالي المدين',
                      value: formatMoneyMinor(_debtorTotalMinor),
                      icon: Icons.south_west_rounded,
                      tint: net.error,
                    ),
                    NetIndicatorTile(
                      label: 'إجمالي الدائن',
                      value: formatMoneyMinor(_creditorTotalMinor),
                      icon: Icons.north_east_rounded,
                      tint: net.success,
                    ),
                  ],
                ),
                const SizedBox(height: NetSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      size: NetSizes.iconSm,
                      color: palette.primary,
                    ),
                    const SizedBox(width: NetSpacing.xs),
                    Expanded(
                      child: Text(
                        'توزيع الأرصدة — رسم بياني أفقي',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
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
              ],
            ),
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
            onSubmitted: _load,
            onChanged: (v) {
              if (v.isEmpty) _load();
            },
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الجوال (GSM)...',
              hintStyle: TextStyle(
                fontFamily: NetTypography.family,
                color: palette.textTertiary,
                fontSize: 13,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load();
                      },
                    ),
              filled: true,
              fillColor: palette.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: NetSpacing.md,
                vertical: NetSpacing.md,
              ),
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
            ),
            style: TextStyle(
              fontFamily: NetTypography.family,
              color: palette.textPrimary,
            ),
          ),
        ),

        // ── شرائح الفلترة ──
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: NetSpacing.pageH,
            children: [
              _chip('الكل (${_allRows.length})', _AccountFilter.all),
              _chip('مدين', _AccountFilter.debtor),
              _chip('دائن', _AccountFilter.creditor),
              _chip(
                'غير مربوط (${_allRows.where((r) => !r.hasPhone).length})',
                _AccountFilter.unlinked,
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
              : _error != null
                  ? AsyncErrorView(
                      message: _error!,
                      onRetry: () => _load(_searchCtrl.text),
                    )
                  : visible.isEmpty
                      ? AsyncEmptyView(
                          message: _filter == _AccountFilter.unlinked
                              ? 'لا حسابات غير مربوطة'
                              : 'لا حسابات في هذا التصفية',
                          icon: Icons.people_outline_rounded,
                          hint: _filter == _AccountFilter.unlinked
                              ? 'جميع الحسابات مربوطة بأرقام جوال'
                              : 'جرّب تغيير التصفية أو إضافة حساب جديد',
                          actionLabel: 'إضافة حساب',
                          onAction: _showCreateSheet,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(_searchCtrl.text),
                          color: palette.primary,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              top: NetSpacing.xs,
                              bottom: 88,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: NetSpacing.sm),
                            itemBuilder: (_, i) {
                              final row = visible[i];
                              void open() {
                                AppRoutes.openCustomerDetail(
                                  context,
                                  row.customer.id,
                                ).then((_) => _load(_searchCtrl.text));
                              }
                              return _AccountCard(
                                row: row,
                                onTap: open,
                                onLongPress: open,
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _chip(String label, _AccountFilter value) {
    final palette = KayanPalette.of(context);
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NetSpacing.sm),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        label: Text(
          label,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: selected ? Colors.white : palette.textPrimary,
          ),
        ),
        selectedColor: palette.primary,
        backgroundColor: palette.surface,
        side: BorderSide(color: selected ? palette.primary : palette.border),
        shape: RoundedRectangleBorder(borderRadius: NetRadii.pillAll),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}
