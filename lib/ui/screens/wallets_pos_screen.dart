import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/entities/pos_account.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

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
    final result = await _editWalletDialog();
    if (result == null || !mounted) return;
    final r = await AppScope.of(context).walletCatalog.saveWallet(name: result.$1);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
    }
    await _load();
  }

  Future<void> _editWallet(Wallet wallet) async {
    final result = await _editWalletDialog(existing: wallet);
    if (result == null || !mounted) return;
    final r = await AppScope.of(context).walletCatalog.updateWallet(
          id: wallet.id,
          name: result.$1,
          status: result.$2,
        );
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
    }
    await _load();
  }

  Future<(String, WalletStatus)?> _editWalletDialog({Wallet? existing}) {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    var status = existing?.status ?? WalletStatus.active;
    return showDialog<(String, WalletStatus)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'محفظة جديدة' : 'تعديل المحفظة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'الاسم'),
                autofocus: true,
              ),
              if (existing != null)
                DropdownButtonFormField<WalletStatus>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: WalletStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(_walletStatusLabel(s))))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setLocal(() => status = value);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (ctrl.text.trim(), status)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _addPos() async {
    final result = await _editPosDialog();
    if (result == null || !mounted) return;
    final c = AppScope.of(context);
    final r = await c.posCatalog.savePointOfSale(name: result.$1);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
      return;
    }
    if (r is Success<PointOfSale>) {
      final pos = r.value;
      await c.posRegistry.save(
        PosAccount(
          posId: pos.id,
          customerId: '',
          name: pos.name,
          identifiers: const [],
          status: pos.status,
          percentageMode: result.$3,
        ),
      );
    }
    await _load();
  }

  Future<void> _editPos(PointOfSale pos) async {
    final c = AppScope.of(context);
    final existingBinding = await c.posRegistry.findByPosId(pos.id);
    PosPercentageMode currentMode = PosPercentageMode.defaultCategory;
    PosAccount? prevAccount;
    if (existingBinding is Success<PosAccount?> && existingBinding.value != null) {
      prevAccount = existingBinding.value;
      currentMode = prevAccount!.percentageMode;
    }
    final result = await _editPosDialog(existing: pos, mode: currentMode);
    if (result == null || !mounted) return;
    final r = await c.posCatalog.updatePointOfSale(
          id: pos.id,
          name: result.$1,
          status: result.$2,
        );
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message)),
      );
      return;
    }
    await c.posRegistry.save(
      PosAccount(
        posId: pos.id,
        customerId: prevAccount?.customerId ?? '',
        name: result.$1,
        identifiers: prevAccount?.identifiers ?? const [],
        notifyPhone: prevAccount?.notifyPhone,
        status: result.$2,
        percentageMode: result.$3,
      ),
    );
    await _load();
  }

  Future<(String, PointOfSaleStatus, PosPercentageMode)?> _editPosDialog({
    PointOfSale? existing,
    PosPercentageMode mode = PosPercentageMode.defaultCategory,
  }) {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    var status = existing?.status ?? PointOfSaleStatus.active;
    var percentageMode = mode;
    return showDialog<(String, PointOfSaleStatus, PosPercentageMode)>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(
              existing == null ? 'نقطة بيع جديدة' : 'تعديل نقطة البيع',
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PosPercentageMode>(
                  value: percentageMode,
                  decoration: const InputDecoration(
                    labelText: 'وضع نسبة العمولة',
                    labelStyle: TextStyle(fontFamily: 'Tajawal'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: PosPercentageMode.defaultCategory,
                      child: Text('نسبة الفئة الافتراضية', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                    DropdownMenuItem(
                      value: PosPercentageMode.zero,
                      child: Text('عمولة صفرية (0%)', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setLocal(() => percentageMode = value);
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PointOfSaleStatus>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'الحالة'),
                    items: PointOfSaleStatus.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(_posStatusLabel(s), style: const TextStyle(fontFamily: 'Tajawal'))))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setLocal(() => status = value);
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (ctrl.text.trim(), status, percentageMode)),
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _showWalletActions(Wallet wallet) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(wallet.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal')),
              onTap: () {
                Navigator.pop(ctx);
                _editWallet(wallet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.pattern),
              title: const Text('إدارة القوالب', style: TextStyle(fontFamily: 'Tajawal')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TemplatesScreen(
                      walletId: wallet.id,
                      walletName: wallet.name,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPosActions(PointOfSale pos) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(pos.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal')),
              onTap: () {
                Navigator.pop(ctx);
                _editPos(pos);
              },
            ),
          ],
        ),
      ),
    );
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
                    _walletList(),
                    _posList(),
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

  Widget _walletList() {
    if (_wallets.isEmpty) {
      return AsyncEmptyView(message: 'لا محافظ', actionLabel: 'إضافة', onAction: _addWallet);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _wallets.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final wallet = _wallets[i];
          return ListTile(
            title: Text(wallet.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            subtitle: Text(_walletStatusLabel(wallet.status), style: const TextStyle(fontFamily: 'Tajawal')),
            leading: const Icon(Icons.account_balance_wallet_outlined, color: KayanColors.primary),
            trailing: IconButton(
              tooltip: 'إجراءات المحفظة',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showWalletActions(wallet),
            ),
            onLongPress: () => _editWallet(wallet),
          );
        },
      ),
    );
  }

  Widget _posList() {
    if (_pos.isEmpty) {
      return AsyncEmptyView(message: 'لا نقاط بيع', actionLabel: 'إضافة', onAction: _addPos);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _pos.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final pos = _pos[i];
          return ListTile(
            title: Text(pos.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            subtitle: Text(_posStatusLabel(pos.status), style: const TextStyle(fontFamily: 'Tajawal')),
            leading: const Icon(Icons.storefront_outlined, color: KayanColors.primary),
            trailing: IconButton(
              tooltip: 'إجراءات نقطة البيع',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showPosActions(pos),
            ),
            onLongPress: () => _editPos(pos),
          );
        },
      ),
    );
  }
}

String _walletStatusLabel(WalletStatus status) {
  return switch (status) {
    WalletStatus.active => 'نشطة',
    WalletStatus.suspended => 'موقوفة',
    WalletStatus.archived => 'مؤرشفة',
  };
}

String _posStatusLabel(PointOfSaleStatus status) {
  return switch (status) {
    PointOfSaleStatus.active => 'نشطة',
    PointOfSaleStatus.suspended => 'موقوفة',
    PointOfSaleStatus.archived => 'مؤرشفة',
  };
}
