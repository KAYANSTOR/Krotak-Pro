import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/local_promotion_progress_service.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/customer_promotion_progress.dart';

/// تفاصيل الحساب: رصيد، معرّفات، ربط جوال، تقدم العروض، عمليات.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _loading = true;
  String? _error;
  Customer? _customer;
  List<CustomerIdentifier> _ids = const [];
  Money? _balance;
  List<Transaction> _recent = const [];
  List<PromotionProgress> _promos = const [];

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
    final found = await c.customers.findById(widget.customerId);
    if (!mounted) return;
    if (found is Failure<Customer?>) {
      setState(() {
        _loading = false;
        _error = found.error.message;
      });
      return;
    }
    final customer = (found as Success<Customer?>).value;
    if (customer == null) {
      setState(() {
        _loading = false;
        _error = 'الحساب غير موجود';
      });
      return;
    }

    final idsR = await c.customers.listIdentifiers(widget.customerId);
    final balR = await c.balanceService.getBalance(widget.customerId, currencyCode: 'YER');
    final txR = await c.transactions.findByCustomer(widget.customerId);
    final promoR = await c.promotionProgress.forCustomer(widget.customerId);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _customer = customer;
      _ids = idsR is Success<List<CustomerIdentifier>> ? idsR.value : const [];
      _balance = balR is Success<Money> ? balR.value : null;
      _recent = txR is Success<List<Transaction>>
          ? (txR.value.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(20).toList()
          : const [];
      _promos = promoR is Success<List<PromotionProgress>> ? promoR.value : const [];
    });
  }

  bool get _hasPrimaryPhone =>
      _ids.any((e) => e.type == CustomerIdentifierType.phoneNumber && e.isPrimary);

  Future<void> _linkPhone() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ربط رقم الجوال', style: TextStyle(fontFamily: 'Tajawal')),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              labelText: 'رقم يبدأ بـ 7 (9 أرقام)',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ربط', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    final phone = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (!RegExp(r'^7\d{8}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم غير صالح', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    final r = await AppScope.of(context).customerService.bindPrimaryGsm(
      customerId: widget.customerId,
      phone: phone,
    );
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  Future<void> _adjustBalance() async {
    final ctrl = TextEditingController();
    var credit = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('تعديل الرصيد', style: TextStyle(fontFamily: 'Tajawal')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('إيداع')),
                    ButtonSegment(value: false, label: Text('خصم')),
                  ],
                  selected: {credit},
                  onSelectionChanged: (s) => setLocal(() => credit = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تنفيذ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      ),
    );
    final raw = ctrl.text.trim().replaceAll(',', '');
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final major = num.tryParse(raw);
    if (major == null || major <= 0) return;
    final amount = Money(minorUnits: (major * 100).round(), currencyCode: 'YER');
    final c = AppScope.of(context);
    final r = credit
        ? await c.balanceService.credit(
            customerId: widget.customerId,
            amount: amount,
            reference: 'manual-credit:${c.ids.next('adj')}',
          )
        : await c.balanceService.debit(
            customerId: widget.customerId,
            amount: amount,
            reference: 'manual-debit:${c.ids.next('adj')}',
          );
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  String _fmtMoney(Money? m) {
    if (m == null) return '—';
    final major = m.minorUnits / 100.0;
    return '${major.toStringAsFixed(m.minorUnits % 100 == 0 ? 0 : 2)} ${m.currencyCode}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _customer?.displayName ?? 'تفاصيل الحساب',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        _BalanceHeader(
                          name: _customer!.displayName,
                          balanceLabel: _fmtMoney(_balance),
                          unbound: !_hasPrimaryPhone,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _linkPhone,
                              icon: const Icon(Icons.link, size: 18),
                              label: Text(
                                _hasPrimaryPhone ? 'تغيير الجوال' : 'ربط الجوال',
                                style: const TextStyle(fontFamily: 'Tajawal'),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _adjustBalance,
                              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                              label: const Text('تعديل الرصيد', style: TextStyle(fontFamily: 'Tajawal')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'المعرّفات',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_ids.isEmpty)
                          const Text(
                            'لا معرّفات',
                            style: TextStyle(fontFamily: 'Tajawal', color: Color(0xFF64748B)),
                          )
                        else
                          ..._ids.map(
                            (id) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                id.type == CustomerIdentifierType.phoneNumber
                                    ? Icons.phone_android
                                    : Icons.tag,
                                size: 20,
                                color: KayanColors.primary,
                              ),
                              title: Text(
                                id.value,
                                style: const TextStyle(fontFamily: 'Tajawal'),
                              ),
                              subtitle: Text(
                                '${id.type.name}${id.isPrimary ? ' · أساسي' : ''}',
                                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        CustomerPromotionProgressSection(
                          items: _promos,
                          onOpenAll: () => showCustomerPromotionSheet(
                            context: context,
                            items: _promos,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'آخر العمليات',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_recent.isEmpty)
                          const Text(
                            'لا عمليات',
                            style: TextStyle(fontFamily: 'Tajawal', color: Color(0xFF64748B)),
                          )
                        else
                          ..._recent.map((tx) {
                            final t = tx.createdAt.toLocal();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                '${tx.type.name} · ${_fmtMoney(tx.amount)}',
                                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                              ),
                              subtitle: Text(
                                '${tx.status.name} · ${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11),
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

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({
    required this.name,
    required this.balanceLabel,
    required this.unbound,
  });

  final String name;
  final String balanceLabel;
  final bool unbound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (unbound)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'غير مربوط',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            balanceLabel,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}
