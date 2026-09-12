import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// الحسابات — بحث + بطاقة حساب (رصيد / مدين / دائن) — B4.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<_AccountRow> _rows = const [];

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
        _rows = const [];
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
      final ids = await c.customers.listIdentifiers(customer.id);
      if (ids is Success<List<CustomerIdentifier>>) {
        final phones = ids.value
            .where((i) => i.type == CustomerIdentifierType.phoneNumber);
        if (phones.isNotEmpty) {
          phone = phones.firstWhere((i) => i.isPrimary, orElse: () => phones.first).value;
        }
      }

      rows.add(_AccountRow(customer: customer, balance: balance, phone: phone));
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  Future<void> _showCreateSheet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة حساب عميل',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      status!,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        color: KayanColors.warning,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setModal(() => busy = true);
                            final c = AppScope.of(ctx);
                            final r = await c.customerService.create(
                              displayName: nameCtrl.text,
                              identifierType:
                                  CustomerIdentifierType.phoneNumber,
                              identifierValue: phoneCtrl.text,
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
                          },
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'حفظ',
                            style: TextStyle(fontFamily: 'Tajawal'),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    if (created == true) await _load(_searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'حسابات العملاء والدفتر',
            style: TextStyle(
              fontFamily: 'Tajawal',
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: _load,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم أو الرقم',
                    hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _load(_searchCtrl.text),
                icon: const Icon(Icons.search),
                tooltip: 'بحث',
              ),
              IconButton.filledTonal(
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'إضافة حساب',
              ),
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
                  : _rows.isEmpty
                      ? AsyncEmptyView(
                          message: 'لا حسابات\nأضف عميلًا أو انتظر إيداعًا من رسالة',
                          icon: Icons.people_outline,
                          actionLabel: 'إضافة حساب',
                          onAction: _showCreateSheet,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(_searchCtrl.text),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final row = _rows[i];
                              return _AccountCard(
                                row: row,
                                onTap: () => AppRoutes.openCustomerDetail(
                                      context,
                                      row.customer.id,
                                    ).then((_) => _load(_searchCtrl.text)),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

final class _AccountRow {
  const _AccountRow({
    required this.customer,
    this.balance,
    this.phone,
  });

  final Customer customer;
  final Money? balance;
  final String? phone;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.row, required this.onTap});

  final _AccountRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final bal = row.balance;
    final units = bal?.minorUnits ?? 0;
    final Color tone;
    final String posture;
    if (units > 0) {
      tone = semantic?.success ?? Colors.green;
      posture = 'رصيد متاح';
    } else if (units < 0) {
      tone = semantic?.rejected ?? cs.error;
      posture = 'مدين';
    } else {
      tone = cs.onSurfaceVariant;
      posture = 'متوازن';
    }

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: tone.withOpacity(0.12),
                child: Icon(Icons.person_outline, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.customer.displayName,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.phone ?? row.customer.id,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      posture,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: tone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bal == null
                        ? '—'
                        : formatMoneyMinor(bal.minorUnits.abs()),
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tone,
                    ),
                  ),
                  Text(
                    bal?.currencyCode ?? 'YER',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
