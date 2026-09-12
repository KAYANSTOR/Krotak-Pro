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

/// تفاصيل الحساب + دفتر الحركات الحقيقي (CREDIT / DEBIT / REVERSAL) — B4.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تفاصيل الحساب',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _IdentityHeader(customer: _customer!, ids: _ids),
                      const SizedBox(height: 12),
                      _BalanceCard(balance: _balance),
                      const SizedBox(height: 20),
                      const Text(
                        'دفتر الحركات',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إيداع · بيع · سحب · تسوية · عكس — من الدفتر الحقيقي',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_txs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: AsyncEmptyView(
                            message: 'لا حركات في الدفتر لهذا الحساب',
                            icon: Icons.receipt_long_outlined,
                          ),
                        )
                      else
                        ..._txs.map((tx) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LedgerRow(tx: tx),
                            )),
                    ],
                  ),
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
    final cs = Theme.of(context).colorScheme;
    final phones = ids
        .where((i) => i.type == CustomerIdentifierType.phoneNumber)
        .map((i) => i.value)
        .toList();
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: KayanColors.primary.withOpacity(0.12),
                  child: const Icon(Icons.person, color: KayanColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.displayName,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'الحالة: ${_statusAr(customer.status)}',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (phones.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...phones.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_android, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(p, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusAr(CustomerStatus s) {
    switch (s) {
      case CustomerStatus.active:
        return 'نشط';
      case CustomerStatus.blacklisted:
        return 'قائمة سوداء';
      case CustomerStatus.merged:
        return 'مدموج';
      case CustomerStatus.archived:
        return 'مؤرشف';
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final Money? balance;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final units = balance?.minorUnits ?? 0;
    final Color tone;
    final String posture;
    final String hint;
    if (units > 0) {
      tone = semantic?.success ?? Colors.green;
      posture = 'رصيد متاح (دائن لصالح العميل)';
      hint = 'يمكن استخدامه للبيع النقدي من الرصيد';
    } else if (units < 0) {
      tone = semantic?.rejected ?? cs.error;
      posture = 'مدين على العميل';
      hint = 'ناتج عن بيع آجل أو حركات مدينة';
    } else {
      tone = cs.onSurfaceVariant;
      posture = 'متوازن';
      hint = 'لا رصيد معلق ولا دين';
    }

    return Material(
      color: tone.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tone.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد الحالي',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              balance == null
                  ? '—'
                  : formatMoneyMinor(balance!.minorUnits.abs()),
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: tone,
              ),
            ),
            Text(
              balance?.currencyCode ?? 'YER',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              posture,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: tone,
              ),
            ),
            Text(
              hint,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
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

  /// CREDIT / DEBIT / REVERSAL presentation per plan.
  static String directionTag(TransactionType t) {
    if (t == TransactionType.reversal) return 'REVERSAL';
    return ledgerDirection(t) > 0 ? 'CREDIT' : 'DEBIT';
  }

  static String statusAr(TransactionStatus s) {
    switch (s) {
      case TransactionStatus.completed:
        return 'مكتملة';
      case TransactionStatus.pending:
        return 'معلّقة';
      case TransactionStatus.reversed:
        return 'معكوسة';
      case TransactionStatus.rejected:
        return 'مرفوضة';
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
    final tag = directionTag(tx.type);

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        typeLabel(tx.type),
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tone,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
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
                  Text(
                    statusAr(tx.status),
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${formatMoneyMinor(tx.amount.minorUnits)}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
