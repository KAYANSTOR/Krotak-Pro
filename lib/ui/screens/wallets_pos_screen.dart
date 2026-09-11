import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/wallet.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';

class WalletsPosScreen extends StatefulWidget {
  const WalletsPosScreen({super.key});

  @override
  State<WalletsPosScreen> createState() => _WalletsPosScreenState();
}

class _WalletsPosScreenState extends State<WalletsPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Wallet> _wallets = const [];
  List<PointOfSale> _pos = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final wallets = await c.wallets.listAll();
    final posResult = await c.pointsOfSale.listAll();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (wallets is Failure) {
        _error = (wallets as Failure).error.message;
        return;
      }
      if (posResult is Failure) {
        _error = (posResult as Failure).error.message;
        return;
      }
      _wallets = (wallets as Success<List<Wallet>>).value;
      _pos = (posResult as Success<List<PointOfSale>>).value;
    });
  }

  Future<void> _addWallet() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('محفظة جديدة'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'الاسم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final c = AppScope.of(context);
    final r = await c.walletCatalog.saveWallet(name: ctrl.text.trim());
    ctrl.dispose();
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
    }
    await _load();
  }

  Future<void> _addPos() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نقطة بيع جديدة'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'الاسم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final c = AppScope.of(context);
    final r = await c.posCatalog.savePointOfSale(name: ctrl.text.trim());
    ctrl.dispose();
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحافظ ونقاط البيع'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'المحافظ'),
            Tab(text: 'نقاط البيع'),
          ],
        ),
      ),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _list(
                      items: _wallets.map((w) => (w.name, w.status.name)).toList(),
                      empty: 'لا محافظ',
                      onAdd: _addWallet,
                    ),
                    _list(
                      items: _pos.map((p) => (p.name, p.status.name)).toList(),
                      empty: 'لا نقاط بيع',
                      onAdd: _addPos,
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabs.index == 0) {
            _addWallet();
          } else {
            _addPos();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _list({
    required List<(String, String)> items,
    required String empty,
    required VoidCallback onAdd,
  }) {
    if (items.isEmpty) {
      return AsyncEmptyView(message: empty, actionLabel: 'إضافة', onAction: onAdd);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final (name, status) = items[i];
          return ListTile(
            title: Text(name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            subtitle: Text(status, style: const TextStyle(fontFamily: 'Tajawal')),
            leading: Icon(
              _tabs.index == 0 ? Icons.account_balance_wallet_outlined : Icons.storefront_outlined,
              color: KayanColors.primary,
            ),
          );
        },
      ),
    );
  }
}
