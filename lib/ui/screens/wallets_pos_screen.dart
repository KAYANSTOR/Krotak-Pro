import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

/// شاشة المحافظ ونقاط البيع — مطابقة 100% لإطارات فيديو Z Net (wallet_t*.jpg).
class WalletsPosScreen extends StatefulWidget {
  const WalletsPosScreen({super.key});

  @override
  State<WalletsPosScreen> createState() => _WalletsPosScreenState();
}

class _WalletsPosScreenState extends State<WalletsPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<Wallet> _wallets = const [];
  Set<String> _togglingIds = {};
  List<PointOfSale> _pos = const [];
  Map<String, PosAccount> _posAccounts = const {};

  static const _brandColors = <String, Color>{
    'جيب': Color(0xFF0EA5E9),
    'جوالي': Color(0xFF8B5CF6),
    'ون كاش': Color(0xFFF59E0B),
    'فلوسك': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppScope.of(context).walletCatalog.ensureDefaultWallets();
      await _load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final wallets = await c.walletCatalog.listEnriched();
    final posResult = await c.pointsOfSale.listAll();
    final accountsMap = <String, PosAccount>{};
    if (posResult is Success<List<PointOfSale>>) {
      for (final p in posResult.value) {
        final r = await c.posRegistry.findByPosId(p.id);
        if (r is Success<PosAccount?> && r.value != null) {
          accountsMap[p.id] = r.value!;
        }
      }
    }
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
      _posAccounts = accountsMap;
    });
  }

  List<Wallet> get _filteredWallets {
    if (_query.isEmpty) return _wallets;
    final q = _query.toLowerCase();
    return _wallets
        .where((w) =>
            w.name.toLowerCase().contains(q) ||
            (w.senderId?.toLowerCase().contains(q) ?? false) ||
            (w.packageName?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  List<PointOfSale> get _filteredPos {
    if (_query.isEmpty) return _pos;
    final q = _query.toLowerCase();
    return _pos.where((p) {
      if (p.name.toLowerCase().contains(q)) return true;
      final acc = _posAccounts[p.id];
      if (acc == null) return false;
      if ((acc.notifyPhone ?? '').contains(q)) return true;
      return acc.identifiers.any((id) => id.toLowerCase().contains(q));
    }).toList();
  }

  Color _colorFor(Wallet w) => _brandColors[w.name] ?? KayanColors.primary;

  Future<void> _toggleWallet(Wallet wallet) async {
    if (_togglingIds.contains(wallet.id)) return;
    final next = wallet.status == WalletStatus.active
        ? WalletStatus.suspended
        : WalletStatus.active;
    setState(() {
      _togglingIds = {..._togglingIds, wallet.id};
      _wallets = [
        for (final w in _wallets)
          if (w.id == wallet.id) w.copyWith(status: next) else w,
      ];
    });
    final r = await AppScope.of(context).walletCatalog.updateWallet(
          id: wallet.id,
          name: wallet.name,
          status: next,
          senderId: wallet.senderId,
          sourceMode: wallet.sourceMode,
          packageName: wallet.packageName,
        );
    if (!mounted) return;
    setState(() {
      final nextSet = {..._togglingIds}..remove(wallet.id);
      _togglingIds = nextSet;
    });
    if (r is Failure) {
      setState(() {
        _wallets = [
          for (final w in _wallets)
            if (w.id == wallet.id) w.copyWith(status: wallet.status) else w,
        ];
      });
      _snack((r as Failure).error.message);
      return;
    }
    _snack(next == WalletStatus.active
        ? 'تم تفعيل محفظة «${wallet.name}»'
        : 'تم إيقاف محفظة «${wallet.name}» — لن تُعالج رسائلها');
  }

  Future<void> _togglePos(PointOfSale pos) async {
    if (_togglingIds.contains(pos.id)) return;
    final next = pos.status == PointOfSaleStatus.active
        ? PointOfSaleStatus.suspended
        : PointOfSaleStatus.active;
    setState(() {
      _togglingIds = {..._togglingIds, pos.id};
      _pos = [
        for (final p in _pos)
          if (p.id == pos.id)
            PointOfSale(id: p.id, name: p.name, status: next, createdAt: p.createdAt)
          else
            p,
      ];
    });
    final r = await AppScope.of(context).posCatalog.updatePointOfSale(
          id: pos.id,
          name: pos.name,
          status: next,
        );
    if (!mounted) return;
    if (r is Success) {
      final acc = _posAccounts[pos.id];
      if (acc != null) {
        await AppScope.of(context).posRegistry.save(acc.copyWith(status: next));
      }
    }
    if (!mounted) return;
    setState(() {
      final nextSet = {..._togglingIds}..remove(pos.id);
      _togglingIds = nextSet;
    });
    if (r is Failure) {
      setState(() {
        _pos = [
          for (final p in _pos)
            if (p.id == pos.id)
              PointOfSale(id: p.id, name: p.name, status: pos.status, createdAt: p.createdAt)
            else
              p,
        ];
      });
      _snack((r as Failure).error.message);
      return;
    }
    _snack(next == PointOfSaleStatus.active
        ? 'تم تفعيل نقطة البيع «${pos.name}»'
        : 'تم إيقاف نقطة البيع «${pos.name}»');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('إدارة المحافظ ونقاط البيع',
              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
          backgroundColor: const Color(0xFFF8FAFC),
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري التحميل…')
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم أو المعرف…',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                      TabBar(
                        controller: _tabs,
                        labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                        tabs: const [Tab(text: 'المحافظ'), Tab(text: 'نقاط البيع')],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [_walletsList(), _posList()],
                        ),
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFDB2777),
          onPressed: () => _tabs.index == 0 ? _load() : _load(),
          label: Text(_tabs.index == 0 ? 'تحديث' : 'تحديث',
              style: const TextStyle(fontFamily: 'Tajawal')),
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }

  Widget _walletsList() {
    final items = _filteredWallets.where((w) => w.status != WalletStatus.archived).toList();
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد محافظ', style: TextStyle(fontFamily: 'Tajawal')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final w = items[i];
          final active = w.status == WalletStatus.active;
          return Card(
            child: ListTile(
              title: Text(w.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
              subtitle: Text('${w.senderId ?? '—'} · ${w.sourceMode.name}',
                  style: const TextStyle(fontFamily: 'Tajawal')),
              trailing: Switch.adaptive(
                value: active,
                activeColor: const Color(0xFF0F766E),
                onChanged: _togglingIds.contains(w.id) ? null : (_) => _toggleWallet(w),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _posList() {
    final items = _filteredPos.where((p) => p.status != PointOfSaleStatus.archived).toList();
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد نقاط بيع', style: TextStyle(fontFamily: 'Tajawal')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = items[i];
          final active = p.status == PointOfSaleStatus.active;
          return Card(
            child: ListTile(
              title: Text(p.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
              trailing: Switch.adaptive(
                value: active,
                activeColor: const Color(0xFF0F766E),
                onChanged: _togglingIds.contains(p.id) ? null : (_) => _togglePos(p),
              ),
            ),
          );
        },
      ),
    );
  }
}
