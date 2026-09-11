import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

class TransactionsLogScreen extends StatefulWidget {
  const TransactionsLogScreen({super.key});

  @override
  State<TransactionsLogScreen> createState() => _TransactionsLogScreenState();
}

class _TransactionsLogScreenState extends State<TransactionsLogScreen> {
  bool _loading = true;
  String? _error;
  List<Transaction> _items = const [];

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
    final r = await c.transactions.listRecent(limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<List<Transaction>>) {
        _items = r.value;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل العمليات')),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const AsyncEmptyView(message: 'لا عمليات مسجّلة')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final tx = _items[i];
                          return ListTile(
                            title: Text(
                              '${tx.type.name} — ${formatMoneyMinor(tx.amount.minorUnits)}',
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                            subtitle: Text(
                              '${tx.status.name} · ${tx.reference ?? tx.id}',
                              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                            ),
                            trailing: Text(
                              '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
