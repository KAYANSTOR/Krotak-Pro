import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

/// سجل العمليات مع فلترة فترة زمنية — 1.0.9.
class TransactionsLogScreen extends StatefulWidget {
  const TransactionsLogScreen({super.key});

  @override
  State<TransactionsLogScreen> createState() => _TransactionsLogScreenState();
}

class _TransactionsLogScreenState extends State<TransactionsLogScreen> {
  bool _loading = true;
  String? _error;
  List<Transaction> _all = const [];
  DateTime? _from;
  DateTime? _to;

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
    final r = await c.transactions.listRecent(limit: 500);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<List<Transaction>>) {
        _all = r.value;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  List<Transaction> get _filtered {
    return _all.where((tx) {
      final t = tx.createdAt.toLocal();
      if (_from != null) {
        final start = DateTime(_from!.year, _from!.month, _from!.day);
        if (t.isBefore(start)) return false;
      }
      if (_to != null) {
        final end = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
        if (t.isAfter(end)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _to = picked);
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل العمليات', style: TextStyle(fontFamily: 'Tajawal')),
          actions: [
            if (_from != null || _to != null)
              IconButton(
                tooltip: 'مسح الفلتر',
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                icon: const Icon(Icons.filter_alt_off),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFrom,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        'من: ${_fmt(_from)}',
                        style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTo,
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(
                        'إلى: ${_fmt(_to)}',
                        style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : items.isEmpty
                          ? const AsyncEmptyView(message: 'لا عمليات في الفترة المحددة')
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final tx = items[i];
                                  final local = tx.createdAt.toLocal();
                                  return ListTile(
                                    title: Text(
                                      '${tx.type.name} — ${formatMoneyMinor(tx.amount.minorUnits)} ر.ي',
                                      style: const TextStyle(fontFamily: 'Tajawal'),
                                    ),
                                    subtitle: Text(
                                      '${tx.status.name} · ${tx.reference ?? tx.id}\n'
                                      '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
                                      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                                    ),
                                    isThreeLine: true,
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
