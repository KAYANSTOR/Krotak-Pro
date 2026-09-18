import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/local_promotion_progress_service.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/customer_promotion_progress.dart';

/// تفاصيل الحساب — رصيد + ربط GSM + تعديل رصيد + تقدم العروض + سجل.
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
    final balR = await c.balanceService.getBalance(
      customerId: widget.customerId,
      currencyCode: 'YER',
    );
    final txR = await c.transactions.findByCustomer(widget.customerId);
    final promoR = await c.promotionProgress.forCustomer(widget.customerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _customer = customer;
      _ids = idsR is Success<List<CustomerIdentifier>> ? idsR.value : const [];
      _balance = balR is Success<Money> ? balR.value : null;
      _recent = txR is Success<List<Transaction>>
          ? (txR.value.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
              .take(20)
              .toList()
          : const [];
      _promos = promoR is Success<List<PromotionProgress>> ? promoR.value : const [];
    });
  }

  bool get _hasPrimaryPhone =>
      _ids.any((e) => e.type == CustomerIdentifierType.phoneNumber && e.isPrimary);

  /// حوار ربط الجوال مطابق لإطار acc_410.
  Future<void> _linkPhone() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.phone_android, color: context.kayan.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ربط رقم جوال (GSM)',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الرجاء إدخال رقم جوال العميل لإرسال الكروت المعلّقة وتأكيد المعاملات المستقبلية.',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  labelText: 'رقم الجوال',
                  hintText: '7xxxxxxxx',
                  labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                  hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
              child: const Text(
                'ربط وصرف الكروت',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
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
        const SnackBar(
          content: Text('رقم غير صالح — 9 أرقام تبدأ بـ 7', style: TextStyle(fontFamily: 'Tajawal')),
        ),
      );
      return;
    }
    final r = await AppScope.of(context).customerService.bindPrimaryGsm(
      customerId: widget.customerId,
      phone: phone,
    );
    if (!mounted) return;
    if (r is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم ربط الجوال', style: TextStyle(fontFamily: 'Tajawal')),
        backgroundColor: KayanColors.success,
      ),
    );
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تعديل الرصيد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('إيداع', style: TextStyle(fontFamily: 'Tajawal'))),
                    ButtonSegment(value: false, label: Text('خصم', style: TextStyle(fontFamily: 'Tajawal'))),
                  ],
                  selected: {credit},
                  onSelectionChanged: (s) => setLocal(() => credit = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
    final Result<Transaction> r;
    if (credit) {
      r = await c.balanceService.credit(
        customerId: widget.customerId,
        amount: amount,
        reference: 'manual-credit:${c.ids.next('adj')}',
      );
    } else {
      r = await c.settlementService.settle(
        customerId: widget.customerId,
        amount: amount,
        reference: 'manual-debit:${c.ids.next('adj')}',
      );
    }
    if (!mounted) return;
    if (r is Failure<Transaction>) {
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
    final s = m.minorUnits % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ر.ي';
  }

  String _fmtTxTime(DateTime t) {
    final local = t.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    if (_loading) return const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: AsyncLoadingView()));
    if (_error != null) return Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: AsyncErrorView(message: _error!, onRetry: _load)));
    if (customer == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AsyncErrorView(message: 'تعذر تحميل الحساب، البيانات غير متاحة.', onRetry: _load),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(
              Icons.arrow_forward,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                customer.displayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                'كشف حساب العميل والعمليات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _load,
              icon: Icon(Icons.refresh_rounded, color: context.kayan.primary),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: context.kayan.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.displayName,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (!_hasPrimaryPhone)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.netColors.warningContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'غير مربوط',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.netColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الرصيد الحالي',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _fmtMoney(_balance),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: context.kayan.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _linkPhone,
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: Text(
                      _hasPrimaryPhone ? 'تغيير الجوال' : 'ربط الجوال',
                      style: const TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _adjustBalance,
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    label: const Text(
                      'تعديل الرصيد',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CustomerPromotionProgressSection(
                items: _promos,
                onOpenAll: () => showCustomerPromotionSheet(
                  context: context,
                  items: _promos,
                ),
              ),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'آخر العمليات',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                ..._recent.map((tx) {
                  final credit = tx.type == TransactionType.deposit ||
                      tx.type == TransactionType.reward;
                  final major = tx.amount.minorUnits / 100.0;
                  final amt = major == major.roundToDouble()
                      ? major.toInt().toString()
                      : major.toStringAsFixed(2);
                  final title = (tx.reference != null && tx.reference!.isNotEmpty)
                      ? tx.reference!
                      : tx.type.name;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          credit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 18,
                          color: credit
                              ? context.netColors.available
                              : context.netColors.rejected,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _fmtTxTime(tx.createdAt),
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${credit ? '+' : '-'}$amt ر.ي',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            color: credit
                                ? context.netColors.available
                                : context.netColors.rejected,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
