import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

/// POS listing report — sales are not keyed by POS in current Domain schema,
/// so this surfaces registered points of sale and their status from repositories.
class PosReportScreen extends StatefulWidget {
  const PosReportScreen({super.key});

  @override
  State<PosReportScreen> createState() => _PosReportScreenState();
}

class _PosReportScreenState extends State<PosReportScreen> {
  bool _loading = true;
  String? _error;
  List<PointOfSale> _items = const [];

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
    final r = await AppScope.of(context).pointsOfSale.listAll();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<List<PointOfSale>>) {
        _items = r.value;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير نقاط البيع')),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const AsyncEmptyView(message: 'لا نقاط بيع مسجّلة')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = _items[i];
                          return ListTile(
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(
                              p.name,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'الحالة: ${p.status.name}',
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
