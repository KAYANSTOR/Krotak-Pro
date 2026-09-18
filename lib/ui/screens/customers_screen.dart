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

/// ورقة توزيع الأرصدة: مؤشرات مجمّعة + رسم بياني أفقي لأعلى الأرصدة.
class _BalancesDistributionSheet extends StatelessWidget {
  const _BalancesDistributionSheet({
    required this.rows,
    required this.accountsCount,
    required this.debtorTotalMinor,
    required this.creditorTotalMinor,
    required this.unlinkedCount,
  });

  final List<_AccountRow> rows;
  final int accountsCount;
  final int debtorTotalMinor;
  final int creditorTotalMinor;
  final int unlinkedCount;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    return NetSheet(
      title: 'توزيع أرصدة الحسابات',
      subtitle: 'مؤشرات عامة وأعلى الأرصدة المسجّلة — عرض فقط',
      icon: Icons.bar_chart_rounded,
      children: [
        NetIndicatorGrid(
          indicators: [
            NetIndicatorTile(
              label: 'الحسابات',
              value: '$accountsCount',
              icon: Icons.groups_rounded,
            ),
            NetIndicatorTile(
              label: 'غير مربوط',
              value: '$unlinkedCount',
              icon: Icons.link_off_rounded,
              tint: net.warning,
            ),
            NetIndicatorTile(
              label: 'إجمالي المدين',
              value: formatMoneyMinor(debtorTotalMinor),
              icon: Icons.south_west_rounded,
              tint: net.error,
            ),
            NetIndicatorTile(
              label: 'إجمالي الدائن',
              value: formatMoneyMinor(creditorTotalMinor),
              icon: Icons.north_east_rounded,
              tint: net.success,
            ),
          ],
        ),
        const SizedBox(height: NetSpacing.lg),
        NetHorizontalBars(
          labelWidth: 88,
          emptyMessage: 'لا توجد أرصدة مسجّلة بعد',
          data: [
            for (final row in rows)
              NetBarDatum(
                label: row.customer.displayName,
                value: (row.balance?.minorUnits ?? 0).abs() / 100,
                color: (row.balance?.minorUnits ?? 0) < 0
                    ? net.error
                    : net.success,
                valueLabel: formatMoneyMinor(
                  (row.balance?.minorUnits ?? 0).abs(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// يفتح تطبيق الاتصال أو الرسائل على رقم العميل — إجراء واجهة فقط.
///
/// لا يرسل شيئاً بنفسه: يعرض الرقم في تطبيق النظام المناسب.
Future<void> _openContact(
  BuildContext context,
  String scheme,
  String phone,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri(scheme: scheme, path: phone),
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          scheme == 'tel' ? 'تعذّر فتح تطبيق الاتصال' : 'تعذّر فتح تطبيق الرسائل',
        ),
      ),
    );
  }
}

/// زر إجراء صغير داخل بطاقة الحساب.
class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NetRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(NetRadii.sm),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: palette.primary),
              const SizedBox(width: NetSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AccountRow {
  const _AccountRow({
    required this.customer,
    this.balance,
    this.phone,
    this.altId,
    this.altLabel,
  });

  final Customer customer;
  final Money? balance;
  final String? phone;
  final String? altId;
  final String? altLabel;

  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.row,
    required this.onTap,
    required this.onLongPress,
  });

  final _AccountRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    final title = row.customer.displayName;
    late final String subtitle;
    late final IconData subIcon;
    if (row.hasPhone) {
      subtitle = row.phone!;
      subIcon = Icons.phone_android_rounded;
    } else if (row.altId != null) {
      subtitle = '${row.altLabel ?? 'الرقم البديل'}: ${row.altId}';
      subIcon = row.altLabel == 'اسم المرسل'
          ? Icons.alternate_email_rounded
          : Icons.tag_rounded;
    } else {
      subtitle = row.customer.id;
      subIcon = Icons.badge_outlined;
    }

    return NetSurfaceCard(
      margin: NetSpacing.pageH,
      onTap: onTap,
      padding: const EdgeInsets.all(NetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NetInitialAvatar(name: title),
              const SizedBox(width: NetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: NetSpacing.xxs),
                    Row(
                      children: [
                        Icon(subIcon, size: 13, color: palette.textTertiary),
                        const SizedBox(width: NetSpacing.xs),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              NetBalancePill(amountMinor: row.balance?.minorUnits ?? 0),
            ],
          ),
          if (row.hasPhone) ...[
            const SizedBox(height: NetSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _ContactButton(
                    icon: Icons.call_rounded,
                    label: 'اتصال',
                    onTap: () =>
                        _openContact(context, 'tel', row.phone!.trim()),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: _ContactButton(
                    icon: Icons.sms_outlined,
                    label: 'رسالة',
                    onTap: () =>
                        _openContact(context, 'sms', row.phone!.trim()),
                  ),
                ),
              ],
            ),
          ],
          if (!row.hasPhone) ...[
            const SizedBox(height: NetSpacing.sm),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: net.errorContainer,
                    borderRadius: NetRadii.xsAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_off_rounded, size: 12, color: net.rejected),
                      const SizedBox(width: NetSpacing.xs),
                      Text(
                        'غير مربوط',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: net.rejected,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'اضغط للتفاصيل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: palette.textTertiary,
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
        ],
      ),
    );
  }
}
