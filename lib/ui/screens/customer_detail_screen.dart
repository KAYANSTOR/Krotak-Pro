import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';

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
        _error = 'العميل غير موجود';
      });
      return;
    }
    final ids = await c.customers.listIdentifiers(customer.id);
    final bal = await c.balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    final txs = await c.transactions.findByCustomer(customer.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _customer = customer;
      _ids = ids is Success<List<CustomerIdentifier>> ? ids.value : const [];
      _balance = bal is Success<Money> ? bal.value : null;
      _txs = txs is Success<List<Transaction>> ? txs.value : const [];
    });
  }

  Future<void> _blacklist() async {
    final c = AppScope.of(context);
    final r = await c.customerService.blacklist(widget.customerId);
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure<void>).error.message)),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer?.displayName ?? 'تفاصيل العميل'),
        actions: [
          if (_customer?.status == CustomerStatus.active)
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: 'قائمة سوداء',
              onPressed: _blacklist,
            ),
        ],
      ),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        title: Text(
                          _customer!.displayName,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'الحالة: ${_customer!.status.name}',
                          style: const TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'الرصيد: ${_balance == null ? '—' : formatMoneyMinor(_balance!.minorUnits)}',
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: KayanColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'المعرّفات',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
                    ),
                    if (_ids.isEmpty)
                      const Text('لا معرّفات', style: TextStyle(fontFamily: 'Tajawal'))
                    else
                      ..._ids.map(
                        (id) => ListTile(
                          dense: true,
                          title: Text(id.value, style: const TextStyle(fontFamily: 'Tajawal')),
                          subtitle: Text(id.type.name, style: const TextStyle(fontFamily: 'Tajawal')),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'الحركات',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
                    ),
                    if (_txs.isEmpty)
                      const AsyncEmptyView(message: 'لا حركات')
                    else
                      ..._txs.reversed.map(
                        (tx) => ListTile(
                          dense: true,
                          title: Text(
                            '${tx.type.name} ${formatMoneyMinor(tx.amount.minorUnits)}',
                            style: const TextStyle(fontFamily: 'Tajawal'),
                          ),
                          subtitle: Text(
                            tx.reference ?? tx.id,
                            style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
