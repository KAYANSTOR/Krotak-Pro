import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../widgets/async_views.dart';

enum _AccountFilter { all, debtor, creditor, unlinked }

/// الحسابات والدفتر — مطابق لفيديو Z Net (فلاتر + بطاقات + رقم بديل).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
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
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final altCtrl = TextEditingController();
    var useAlt = false;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'إضافة حساب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'الاسم (اختياري مع رقم بديل)',
                        labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'تعريف برقم بديل (حساب محفظة / مرجع)',
                        style: TextStyle(fontFamily: 'Tajawal', fontSize: 14),
                      ),
                      subtitle: const Text(
                        'للمشتركين الذين وصل تحويلهم بدون رقم جوال',
                        style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                      ),
                      value: useAlt,
                      activeColor: const Color(0xFF0F766E),
                      onChanged: (v) => setModal(() => useAlt = v),
                    ),
                    if (useAlt) ...[
                      TextField(
                        controller: altCtrl,
                        decoration: InputDecoration(
                          labelText: 'الرقم البديل',
                          hintText: 'مثال: 8929114',
                          labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: useAlt ? 'رقم الجوال (اختياري للربط)' : 'رقم الجوال',
                        labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        status!,
                        style: const TextStyle(fontFamily: 'Tajawal', color: Color(0xFFB45309)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              setModal(() => busy = true);
                              final c = AppScope.of(ctx);
                              final phone = phoneCtrl.text.trim();
                              final alt = altCtrl.text.trim();
                              final name = nameCtrl.text.trim();

                              if (useAlt) {
                                if (alt.isEmpty) {
                                  setModal(() {
                                    busy = false;
                                    status = 'أدخل الرقم البديل';
                                  });
                                  return;
                                }
                                final display = name.isNotEmpty ? name : 'رقم بديل $alt';
                                final r = await c.customerService.create(
                                  displayName: display,
                                  identifierType: CustomerIdentifierType.externalReference,
                                  identifierValue: alt,
                                );
                                if (!ctx.mounted) return;
                                if (r is Failure) {
                                  setModal(() {
                                    busy = false;
                                    status = (r as Failure).error.message;
                                  });
                                  return;
                                }
                                final customer = (r as Success<Customer>).value;
                                if (phone.isNotEmpty) {
                                  final add = await c.customerService.addIdentifier(
                                    customerId: customer.id,
                                    type: CustomerIdentifierType.phoneNumber,
                                    value: phone,
                                    isPrimary: true,
                                  );
                                  if (add is Failure && ctx.mounted) {
                                    setModal(() {
                                      busy = false;
                                      status =
                                          'الحساب أُنشئ لكن فشل ربط الجوال: ${(add as Failure).error.message}';
                                    });
                                    return;
                                  }
                                }
                                if (ctx.mounted) Navigator.pop(ctx, true);
                              } else {
                                if (phone.isEmpty) {
                                  setModal(() {
                                    busy = false;
                                    status = 'أدخل رقم الجوال أو فعّل الرقم البديل';
                                  });
                                  return;
                                }
                                final r = await c.customerService.create(
                                  displayName: name.isNotEmpty ? name : phone,
                                  identifierType: CustomerIdentifierType.phoneNumber,
                                  identifierValue: phone,
                                );
                                if (!ctx.mounted) return;
                                if (r is Success<Customer>) {
                                  Navigator.pop(ctx, true);
                                } else {
                                  setModal(() {
                                    busy = false;
                                    status = (r as Failure).error.message;
                                  });
                                }
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'حفظ',
                              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    altCtrl.dispose();
    if (created == true) await _load(_searchCtrl.text);
  }

  Widget _chip(String label, _AccountFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: FilterChip(
        selected: selected,
        showCheckmark: selected,
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        selectedColor: const Color(0xFF0F766E),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الحسابات والدفتر',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'اضغط مطولًا على أي حساب لتعديل بيانات الحساب.',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // أيقونات الهيدر مطابقة لإطار acc_390 / acc_405
                _roundIcon(Icons.person_add_alt_1, _showCreateSheet),
                const SizedBox(width: 8),
                _roundIcon(
                  Icons.shield_outlined,
                  () => setState(() => _filter = _AccountFilter.unlinked),
                ),
                const SizedBox(width: 8),
                _roundIcon(
                  Icons.volume_up_outlined,
                  () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تنبيهات الحسابات مرتبطة بتنبيه الرسائل المعلّقة',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: _load,
              onChanged: (v) {
                if (v.isEmpty) _load();
              },
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو رقم الجوال (GSM)...',
                hintStyle: TextStyle(
                  fontFamily: 'Tajawal',
                  color: Colors.grey.shade500,
                  fontSize: 13,
                ),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.4),
                ),
              ),
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
            child: Row(
              children: [
                _chip('الكل', _AccountFilter.all),
                _chip('مدين', _AccountFilter.debtor),
                _chip('دائن', _AccountFilter.creditor),
                _chip('غير مربوط', _AccountFilter.unlinked),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const AsyncLoadingView()
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
                            icon: Icons.people_outline,
                            actionLabel: 'إضافة حساب',
                            onAction: _showCreateSheet,
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(_searchCtrl.text),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final row = visible[i];
                                return _VideoAccountCard(
                                  row: row,
                                  onTap: () => AppRoutes.openCustomerDetail(
                                    context,
                                    row.customer.id,
                                  ).then((_) => _load(_searchCtrl.text)),
                                  onLongPress: () => AppRoutes.openCustomerDetail(
                                    context,
                                    row.customer.id,
                                  ).then((_) => _load(_searchCtrl.text)),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: const Color(0xFF334155)),
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

class _VideoAccountCard extends StatelessWidget {
  const _VideoAccountCard({
    required this.row,
    required this.onTap,
    required this.onLongPress,
  });

  final _AccountRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String get _initials {
    final n = row.customer.displayName.trim();
    if (n.isEmpty) return '؟';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    String firstChar(String s) {
      final runes = s.runes;
      if (runes.isEmpty) return '؟';
      return String.fromCharCode(runes.first);
    }

    if (parts.length >= 2) {
      return '${firstChar(parts[0])}${firstChar(parts[1])}';
    }
    final runes = n.runes.toList();
    if (runes.length >= 2) {
      return String.fromCharCodes(runes.take(2));
    }
    return firstChar(n);
  }

  @override
  Widget build(BuildContext context) {
    final units = row.balance?.minorUnits ?? 0;
    final amountText = row.balance == null ? '—' : formatMoneyMinor(units.abs());

    final title = row.customer.displayName;
    late final String subtitle;
    late final IconData subIcon;
    if (row.hasPhone) {
      subtitle = row.phone!;
      subIcon = Icons.phone_android;
    } else if (row.altId != null) {
      subtitle = '${row.altLabel ?? 'الرقم البديل'}: ${row.altId}';
      subIcon = row.altLabel == 'اسم المرسل' ? Icons.alternate_email : Icons.tag;
    } else {
      subtitle = row.customer.id;
      subIcon = Icons.badge_outlined;
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$amountText ر.ي',
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                  if (!row.hasPhone) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_off, size: 12, color: Color(0xFFDC2626)),
                          SizedBox(width: 4),
                          Text(
                            'غير مربوط',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            subtitle,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(subIcon, size: 14, color: Colors.grey.shade500),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFCCFBF1),
                child: Text(
                  _initials,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
