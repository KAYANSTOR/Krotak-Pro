import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/ledger.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// تفاصيل الحساب + ربط الجوال + دمج عند التعارض — مطابق فيديو Z Net.
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
  bool _linking = false;

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

    final list = List<Transaction>.of(
      (txs as Success<List<Transaction>>).value,
    );
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _loading = false;
      _customer = customer;
      _ids = (ids as Success<List<CustomerIdentifier>>).value;
      _balance = (bal as Success<Money>).value;
      _txs = list;
    });
  }

  Future<void> _showLinkPhoneDialog() async {
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.phone_android, color: Color(0xFF0F766E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ربط رقم جوال (GSM)',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الرجاء إدخال رقم جوال المشترك لإرسال الكروت المعلّقة وتأكيد المعاملات المستقبلية.',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
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
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'ربط وصرف الكروت',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
    final phone = phoneCtrl.text.trim();
    phoneCtrl.dispose();
    if (ok != true || phone.isEmpty || !mounted) return;
    await _linkPhone(phone);
  }

  Future<void> _linkPhone(String phone) async {
    setState(() => _linking = true);
    final c = AppScope.of(context);

    // Conflict? another customer already owns this phone → offer merge.
    final existing = await c.customers.findByIdentifier(phone);
    if (!mounted) return;
    if (existing is Success<Customer?> &&
        existing.value != null &&
        existing.value!.id != widget.customerId) {
      setState(() => _linking = false);
      await _confirmMerge(
        sourceId: widget.customerId,
        targetId: existing.value!.id,
        target: existing.value!,
        phone: phone,
      );
      return;
    }

    final result = await c.customerService.addIdentifier(
      customerId: widget.customerId,
      type: CustomerIdentifierType.phoneNumber,
      value: phone,
      isPrimary: true,
    );
    if (!mounted) return;
    setState(() => _linking = false);
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم ربط رقم الجوال بنجاح', style: TextStyle(fontFamily: 'Tajawal')),
      ),
    );
    await _load();
  }

  Future<void> _confirmMerge({
    required String sourceId,
    required String targetId,
    required Customer target,
    required String phone,
  }) async {
    final reasonCtrl = TextEditingController(text: 'نفس المشترك برقم بديل');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'دمج حسابات المشترك',
              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الرقم $phone مربوط مسبقًا بحساب «${target.displayName}».\n'
                    'سيتم دمج الحساب الحالي في الحساب الرئيسي ونقل المعرّفات.',
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: 'سبب الدمج (إلزامي)',
                      labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text(
                  'تأكيد الدمج والصرف',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _linking = true);
    final c = AppScope.of(context);
    // Merge current (source / alternate) INTO the phone owner (target).
    final merged = await c.mergeService.merge(
      sourceCustomerId: sourceId,
      targetCustomerId: targetId,
    );
    if (!mounted) return;
    setState(() => _linking = false);
    if (merged is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (merged as Failure).error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم الدمج: $reason',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // leave merged account detail
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
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const Text(
                'كشف حساب المشترك والعمليات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
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
                            const SizedBox(height: 12),
                            if (!_hasPhone) ...[
                              _UnlinkedBanner(
                                onLink: _linking ? null : _showLinkPhoneDialog,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _IdentityHeader(customer: _customer!, ids: _ids),
                            const SizedBox(height: 20),
                            const Text(
                              'دفتر الحركات',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
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
                      if (_linking)
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
          const Text(
            'الرصيد الحالي',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: Color(0xFF047857),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            balance == null ? '—' : '${formatMoneyMinor(units.abs())} ر.ي',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: Color(0xFF065F46),
            ),
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
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFF0F766E)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'مشترك غير مربوط برقم جوال',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'هذا العميل معرّف بهوية خصوصية (اسم أو رقم بديل). اربط رقم جوال يدوي لتفعيل إرسال الكروت اليدوية أو الآلية له.',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              height: 1.4,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onLink,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.link, size: 18),
            label: const Text(
              'ربط رقم جوال الآن',
              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.customer, required this.ids});

  final Customer customer;
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
            Text(
              'المعرّفات',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            if (ids.isEmpty)
              Text(
                'لا معرّفات',
                style: TextStyle(fontFamily: 'Tajawal', color: Colors.grey.shade600),
              )
            else
              ...ids.map((id) {
                final label = switch (id.type) {
                  CustomerIdentifierType.phoneNumber => 'جوال',
                  CustomerIdentifierType.username => 'اسم',
                  CustomerIdentifierType.externalReference => 'رقم بديل',
                };
                final icon = switch (id.type) {
                  CustomerIdentifierType.phoneNumber => Icons.phone_android,
                  CustomerIdentifierType.username => Icons.alternate_email,
                  CustomerIdentifierType.externalReference => Icons.tag,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: KayanColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '$label: ${id.value}${id.isPrimary ? ' · أساسي' : ''}',
                        style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                      ),
                    ],
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

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final dir = ledgerDirection(tx.type);
    final isReversal = tx.type == TransactionType.reversal;
    final Color tone;
    if (isReversal) {
      tone = semantic?.warning ?? Colors.orange;
    } else if (dir > 0) {
      tone = semantic?.success ?? Colors.green;
    } else {
      tone = semantic?.rejected ?? cs.error;
    }
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
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: tone,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    typeLabel(tx.type),
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _fmtTime(tx.createdAt),
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (tx.reference != null && tx.reference!.isNotEmpty)
                    Text(
                      'مرجع: ${tx.reference}',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              dir > 0 ? Icons.arrow_downward : Icons.arrow_upward,
              size: 18,
              color: tone,
            ),
          ],
        ),
      ),
    );
  }
}
