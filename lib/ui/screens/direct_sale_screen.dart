import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

class DirectSaleScreen extends StatefulWidget {
  const DirectSaleScreen({super.key});

  @override
  State<DirectSaleScreen> createState() => _DirectSaleScreenState();
}

class _DirectSaleScreenState extends State<DirectSaleScreen> {
  bool _loading = true;
  String? _error;
  List<Customer> _customers = const [];
  List<domain.CardCategory> _categories = const [];
  String? _customerId;
  String? _categoryId;
  bool _busy = false;
  String? _status;
  String? _saleOperationId;

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
    final customers = await c.customers.search('');
    final cats = await c.categories.listAll();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (customers is Failure || cats is Failure) {
        _error = 'تعذر تحميل بيانات البيع';
        return;
      }
      _customers = (customers as Success<List<Customer>>)
          .value
          .where((e) => e.status == CustomerStatus.active)
          .toList();
      _categories = (cats as Success<List<domain.CardCategory>>)
          .value
          .where((e) => e.isActive)
          .toList();
    });
  }

  Future<void> _sell() async {
    if (_customerId == null || _categoryId == null) {
      setState(() => _status = 'اختر العميل والفئة');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final operationId = _saleOperationId ??= c.ids.next('sale-op');
    final r = await c.saleService.sellFromBalance(
      customerId: _customerId!,
      categoryId: _categoryId!,
      operationId: operationId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r is Success<Sale>) {
        _status = 'تم البيع: ${r.value.id}';
        _saleOperationId = null;
      } else {
        // Keep the operation id so a retry of the same user action is
        // idempotent. Changing either selection below creates a new operation.
        _status = (r as Failure).error.message;
      }
    });
  }

  void _selectCustomer(String? value) {
    setState(() {
      _customerId = value;
      _saleOperationId = null;
    });
  }

  void _selectCategory(String? value) {
    setState(() {
      _categoryId = value;
      _saleOperationId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيع مباشر')),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<String>(
                      value: _customerId,
                      decoration: const InputDecoration(
                        labelText: 'العميل',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final cu in _customers)
                          DropdownMenuItem(value: cu.id, child: Text(cu.displayName)),
                      ],
                      onChanged: _selectCustomer,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'فئة الكرت',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final cat in _categories)
                          DropdownMenuItem(
                            value: cat.id,
                            child: Text(
                              '${cat.name} — ${formatMoneyMinor(cat.faceValue.minorUnits)}',
                            ),
                          ),
                      ],
                      onChanged: _selectCategory,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _sell,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تنفيذ البيع'),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(_status!, style: const TextStyle(fontFamily: 'Tajawal')),
                    ],
                  ],
                ),
    );
  }
}
