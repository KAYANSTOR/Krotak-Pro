import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/entities/pos_account.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

/// شاشة المحافظ ونقاط البيع — تصميم مطابق للصورة المرجعية Z Net.
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
  List<PointOfSale> _pos = const [];

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
    return _pos.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Color _colorFor(Wallet w) {
    return _brandColors[w.name] ?? KayanColors.primary;
  }

  Future<void> _toggleWallet(Wallet wallet) async {
    final next = wallet.status == WalletStatus.active
        ? WalletStatus.suspended
        : WalletStatus.active;
    final r = await AppScope.of(context).walletCatalog.updateWallet(
          id: wallet.id,
          name: wallet.name,
          status: next,
          senderId: wallet.senderId,
          sourceMode: wallet.sourceMode,
          packageName: wallet.packageName,
        );
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
    }
    await _load();
  }

  Future<void> _addWallet() async {
    final result = await _editWalletDialog();
    if (result == null || !mounted) return;
    final r = await AppScope.of(context).walletCatalog.saveWallet(
          name: result.$1,
          senderId: result.$2,
          sourceMode: result.$3,
          packageName: result.$4,
        );
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
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
          status: result.$5,
          senderId: result.$2,
          sourceMode: result.$3,
          packageName: result.$4,
        );
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
    }
    await _load();
  }

  /// Returns (name, senderId, sourceMode, packageName, status)
  Future<(String, String?, WalletSourceMode, String?, WalletStatus)?> _editWalletDialog({
    Wallet? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final senderCtrl = TextEditingController(text: existing?.senderId ?? '');
    final pkgCtrl = TextEditingController(text: existing?.packageName ?? '');
    var mode = existing?.sourceMode ?? WalletSourceMode.notification;
    var status = existing?.status ?? WalletStatus.active;

    return showDialog<(String, String?, WalletSourceMode, String?, WalletStatus)>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existing == null ? 'محفظة جديدة' : 'تعديل المحفظة',
              style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      labelStyle: TextStyle(fontFamily: 'Tajawal'),
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: senderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'معرف المرسل (Sender ID)',
                      labelStyle: TextStyle(fontFamily: 'Tajawal'),
                      hintText: 'مثال: JAIB',
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                  const SizedBox(height: 12),
                  const Text('مصدر الاستقبال', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<WalletSourceMode>(
                    segments: const [
                      ButtonSegment(
                        value: WalletSourceMode.notification,
                        label: Text('إشعار', style: TextStyle(fontFamily: 'Tajawal')),
                        icon: Icon(Icons.notifications_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: WalletSourceMode.sms,
                        label: Text('SMS', style: TextStyle(fontFamily: 'Tajawal')),
                        icon: Icon(Icons.sms_outlined, size: 18),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setLocal(() => mode = s.first),
                  ),
                  if (mode == WalletSourceMode.notification) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pkgCtrl,
                      decoration: const InputDecoration(
                        labelText: 'حزمة التطبيق (Package Name)',
                        labelStyle: TextStyle(fontFamily: 'Tajawal'),
                        hintText: 'com.example.app',
                      ),
                      style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                    ),
                  ],
                  if (existing != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WalletStatus>(
                      value: status,
                      decoration: const InputDecoration(
                        labelText: 'الحالة',
                        labelStyle: TextStyle(fontFamily: 'Tajawal'),
                      ),
                      items: WalletStatus.values
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(_walletStatusLabel(s), style: const TextStyle(fontFamily: 'Tajawal')),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => status = v);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: KayanColors.primary),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(
                    ctx,
                    (
                      name,
                      senderCtrl.text.trim().isEmpty ? null : senderCtrl.text.trim(),
                      mode,
                      mode == WalletSourceMode.notification && pkgCtrl.text.trim().isNotEmpty
                          ? pkgCtrl.text.trim()
                          : null,
                      status,
                    ),
                  );
                },
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      senderCtrl.dispose();
      pkgCtrl.dispose();
    });
  }

  Future<void> _addPos() async {
    final result = await _editPosDialog();
    if (result == null || !mounted) return;
    final c = AppScope.of(context);
    final r = await c.posCatalog.savePointOfSale(name: result.$1);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
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
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existing == null ? 'نقطة بيع جديدة' : 'تعديل نقطة البيع',
              style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم',
                    labelStyle: TextStyle(fontFamily: 'Tajawal'),
                  ),
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
                    decoration: const InputDecoration(
                      labelText: 'الحالة',
                      labelStyle: TextStyle(fontFamily: 'Tajawal'),
                    ),
                    items: PointOfSaleStatus.values
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(_posStatusLabel(s), style: const TextStyle(fontFamily: 'Tajawal')),
                            ))
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: KayanColors.primary),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                title: Text(
                  wallet.name,
                  style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 16),
                ),
                subtitle: wallet.packageName != null
                    ? Text(wallet.packageName!, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12))
                    : null,
              ),
              const Divider(height: 1),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showPosActions(PointOfSale pos) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                title: Text(
                  pos.name,
                  style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal')),
                onTap: () {
                  Navigator.pop(ctx);
                  _editPos(pos);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: KayanColors.appBackground,
        body: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 4),
              child: Row(
                children: [
                  // RTL: first = right side → title
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المحافظ ونقاط البيع',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: KayanColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'إدارة مصادر الدفع ونقاط البيع',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 13,
                            color: KayanColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _RoundIcon(
                    icon: Icons.refresh,
                    onTap: _load,
                  ),
                ],
              ),
            ),

            // ── Search ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontFamily: 'Tajawal'),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الحزمة...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: KayanColors.textTertiary,
                  ),
                  prefixIcon: const Icon(Icons.search, color: KayanColors.textTertiary),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),

            // ── Custom Tabs ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _TabChip(
                    label: 'المحافظ',
                    selected: _tabs.index == 0,
                    onTap: () {
                      _tabs.animateTo(0);
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: 'نقاط البيع',
                    selected: _tabs.index == 1,
                    onTap: () {
                      _tabs.animateTo(1);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Body ────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _buildWalletsTab(),
                            _buildPosTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletsTab() {
    final list = _filteredWallets;
    return Column(
      children: [
        Expanded(
          child: list.isEmpty
              ? AsyncEmptyView(
                  message: _query.isEmpty ? 'لا محافظ بعد' : 'لا نتائج للبحث',
                  actionLabel: _query.isEmpty ? 'إضافة محفظة' : null,
                  onAction: _query.isEmpty ? _addWallet : null,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KayanColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final w = list[i];
                      return _WalletCard(
                        wallet: w,
                        brandColor: _colorFor(w),
                        onToggle: () => _toggleWallet(w),
                        onMenu: () => _showWalletActions(w),
                        onTap: () => _editWallet(w),
                      );
                    },
                  ),
                ),
        ),
        // Full-width pink add button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: KayanColors.accentPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _addWallet,
              icon: const Icon(Icons.add, size: 22),
              label: const Text(
                'إضافة محفظة',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPosTab() {
    final list = _filteredPos;
    return Column(
      children: [
        Expanded(
          child: list.isEmpty
              ? AsyncEmptyView(
                  message: _query.isEmpty ? 'لا نقاط بيع بعد' : 'لا نتائج للبحث',
                  actionLabel: _query.isEmpty ? 'إضافة نقطة بيع' : null,
                  onAction: _query.isEmpty ? _addPos : null,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KayanColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return _PosCard(
                        pos: p,
                        onMenu: () => _showPosActions(p),
                        onTap: () => _editPos(p),
                      );
                    },
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: KayanColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _addPos,
              icon: const Icon(Icons.add, size: 22),
              label: const Text(
                'إضافة نقطة بيع',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE8EEF2),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: KayanColors.textPrimary),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? KayanColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: KayanColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? Colors.white : KayanColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.brandColor,
    required this.onToggle,
    required this.onMenu,
    required this.onTap,
  });
  final Wallet wallet;
  final Color brandColor;
  final VoidCallback onToggle;
  final VoidCallback onMenu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = wallet.status == WalletStatus.active;
    final isNotif = wallet.sourceMode == WalletSourceMode.notification;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Colored strip (RTL → appears on the right)
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: brandColor,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Icon box
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      wallet.name.isNotEmpty ? wallet.name.characters.first : '؟',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: brandColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Texts
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          wallet.name,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: KayanColors.textPrimary,
                          ),
                        ),
                        if (wallet.senderId != null && wallet.senderId!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            wallet.senderId!,
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12,
                              color: KayanColors.textSecondary,
                            ),
                          ),
                        ],
                        if (isNotif && wallet.packageName != null && wallet.packageName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            wallet.packageName!,
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              color: KayanColors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isNotif
                                ? const Color(0xFFDBEAFE)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isNotif ? '🔔 إشعار' : 'SMS',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isNotif
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Switch + menu
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Switch.adaptive(
                      value: isActive,
                      activeColor: KayanColors.primary,
                      onChanged: (_) => onToggle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: onMenu,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosCard extends StatelessWidget {
  const _PosCard({
    required this.pos,
    required this.onMenu,
    required this.onTap,
  });
  final PointOfSale pos;
  final VoidCallback onMenu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = pos.status == PointOfSaleStatus.active;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KayanColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.storefront_outlined, color: KayanColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pos.name,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: KayanColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'نشطة' : _posStatusLabel(pos.status),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? const Color(0xFF047857)
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: onMenu,
              ),
            ],
          ),
        ),
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
