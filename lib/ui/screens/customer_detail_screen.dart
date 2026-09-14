import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/ledger.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// تفاصيل الحساب — رصيد · ربط جوال · تعديل رصيد · صرف كرت · دفتر.
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
  Money? _balance;
  List<CustomerIdentifier> _ids = const [];
  List<Transaction> _txs = const [];
  bool _busy = false;

  bool get _hasPhone =>
      _ids.any((i) => i.type == CustomerIdentifierType.phoneNumber);

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
    final ids = await c.customers.listIdentifiers(widget.customerId);
    final bal = await c.balanceService.getBalance(
      customerId: widget.customerId,
      currencyCode: 'YER',
    );
    final txs = await c.transactions.findByCustomer(widget.customerId);

    if (!mounted) return;
    if (found is Failure || ids is Failure || bal is Failure || txs is Failure) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الحساب';
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

    final list = List<Transaction>.of((txs as Success<List<Transaction>>).value);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _loading = false;
      _customer = customer;
      _ids = (ids as Success<List<CustomerIdentifier>>).value;
      _balance = (bal as Success<Money>).value;
      _txs = list;
    });
  }

  Future<void> _adjustBalance() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تعديل الرصيد (إيداع)', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'المبلغ (ر.ي)',
              labelStyle: const TextStyle(fontFamily: 'Tajawal'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إيداع', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    final raw = ctrl.text.trim().replaceAll(',', '');
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final major = num.tryParse(raw);
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مبلغ غير صالح', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    setState(() => _busy = true);
    final c = AppScope.of(context);
    final r = await c.balanceService.credit(
      customerId: widget.customerId,
      amount: Money(minorUnits: (major * 100).round(), currencyCode: 'YER'),
      reference: 'manual-credit:${c.ids.next('adj')}',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  Future<void> _issueCard() async {
    final c = AppScope.of(context);
    final cats = await c.categories.listAll();
    if (!mounted) return;
    final active = cats is Success<List<CardCategory>>
        ? cats.value.where((e) => e.isActive).toList()
        : const <CardCategory>[];
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا فئات كروت نشطة', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    String selected = active.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('صرف كرت من الرصيد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
            content: DropdownButtonFormField<String>(
              value: selected,
              decoration: InputDecoration(
                labelText: 'الفئة',
                labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                for (final cat in active)
                  DropdownMenuItem(
                    value: cat.id,
                    child: Text(
                      '${cat.name} · ${formatMoneyMinor(cat.faceValue.minorUnits)} ر.ي',
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setModal(() => selected = v);
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('صرف', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await c.saleService.sellFromBalance(
      customerId: widget.customerId,
      categoryId: selected,
      operationId: c.ids.next('sale'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    final sale = (r as Success<Sale>).value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم صرف الكرت: ${sale.cardId}', style: const TextStyle(fontFamily: 'Tajawal'))),
    );
    await _load();
  }

  Future<void> _showLinkPhoneDialog() async {
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('ربط رقم جوال (GSM)', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
          content: TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'رقم الجوال',
              hintText: '7xxxxxxxx',
              labelStyle: const TextStyle(fontFamily: 'Tajawal'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ربط وصرف الكروت', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    final phone = phoneCtrl.text.trim();
    phoneCtrl.dispose();
    if (ok != true || phone.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final c = AppScope.of(context);
    final existing = await c.customers.findByIdentifier(phone);
    if (!mounted) return;
    if (existing is Success<Customer?> &&
        existing.value != null &&
        existing.value!.id != widget.customerId) {
      setState(() => _busy = false);
      final target = existing.value!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('دمج حسابات المشترك', style: TextStyle(fontFamily: 'Tajawal')),
          content: Text(
            'الرقم مربوط بحساب «${target.displayName}». دمج الحساب الحالي فيه؟',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دمج', style: TextStyle(fontFamily: 'Tajawal'))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final merged = await c.mergeService.merge(
        sourceCustomerId: widget.customerId,
        targetCustomerId: target.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (merged is Failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((merged as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
        );
        return;
      }
      Navigator.of(context).pop();
      return;
    }
    final result = await c.customerService.addIdentifier(
      customerId: widget.customerId,
      type: CustomerIdentifierType.phoneNumber,
      value: phone,
      isPrimary: true,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _customer?.displayName ?? 'تفاصيل الحساب',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const Text(
                'كشف حساب المشترك والعمليات',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            _BalanceHero(balance: _balance),
                            const SizedBox(height: 10),
                            // Video action row: تعديل الرصيد | العروض | صرف كرت
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionChip(
                                    icon: Icons.tune,
                                    label: 'تعديل الرصيد',
                                    onTap: _busy ? null : _adjustBalance,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ActionChip(
                                    icon: Icons.local_offer_outlined,
                                    label: 'العروض',
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'العروض من تبويب العروض الرئيسي',
                                            style: TextStyle(fontFamily: 'Tajawal'),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ActionChip(
                                    icon: Icons.sim_card_outlined,
                                    label: 'صرف كرت',
                                    onTap: _busy ? null : _issueCard,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!_hasPhone) ...[
                              _UnlinkedBanner(onLink: _busy ? null : _showLinkPhoneDialog),
                              const SizedBox(height: 12),
                            ],
                            _IdentityHeader(ids: _ids),
                            const SizedBox(height: 20),
                            const Text(
                              'دفتر الحركات',
                              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            if (_txs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: AsyncEmptyView(
                                  message: 'لا حركات في الدفتر لهذا الحساب',
                                  icon: Icons.receipt_long_outlined,
                                ),
                              )
                            else
                              ..._txs.map(
                                (tx) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _LedgerRow(tx: tx),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_busy)
                        Container(
                          color: Colors.black26,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance});
  final Money? balance;

  @override
  Widget build(BuildContext context) {
    final units = balance?.minorUnits ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        children: [
          const Text('الرصيد الحالي', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, color: Color(0xFF047857))),
          const SizedBox(height: 4),
          Text(
            balance == null ? '—' : '${formatMoneyMinor(units.abs())} ر.ي',
            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w900, fontSize: 28, color: Color(0xFF065F46)),
          ),
        ],
      ),
    );
  }
}

class _UnlinkedBanner extends StatelessWidget {
  const _UnlinkedBanner({required this.onLink});
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مشترك غير مربوط برقم جوال',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'اربط رقم جوال لتفعيل إرسال الكروت اليدوية أو الآلية.',
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onLink,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('ربط رقم جوال الآن', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.ids});
  final List<CustomerIdentifier> ids;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('المعرّفات', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (ids.isEmpty)
              const Text('لا معرّفات', style: TextStyle(fontFamily: 'Tajawal'))
            else
              ...ids.map((id) {
                final label = switch (id.type) {
                  CustomerIdentifierType.phoneNumber => 'جوال',
                  CustomerIdentifierType.username => 'اسم',
                  CustomerIdentifierType.externalReference => 'رقم بديل',
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '$label: ${id.value}${id.isPrimary ? ' · أساسي' : ''}',
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.tx});
  final Transaction tx;

  static String typeLabel(TransactionType t) {
    switch (t) {
      case TransactionType.deposit:
        return 'إيداع';
      case TransactionType.withdrawal:
        return 'سحب';
      case TransactionType.sale:
        return 'بيع';
      case TransactionType.settlement:
        return 'تسوية';
      case TransactionType.reversal:
        return 'عكس';
      case TransactionType.advance:
        return 'سلفة';
      case TransactionType.reward:
        return 'مكافأة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final dir = ledgerDirection(tx.type);
    final tone = dir > 0 ? (semantic?.success ?? Colors.green) : (semantic?.rejected ?? cs.error);
    final sign = dir > 0 ? '+' : '−';
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$sign${formatMoneyMinor(tx.amount.minorUnits)}',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, color: tone),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                typeLabel(tx.type),
                textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
