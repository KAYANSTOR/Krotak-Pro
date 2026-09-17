import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

/// شاشة المحافظ ونقاط البيع — مطابقة 100% لإطارات فيديو Z Net (wallet_t*.jpg).
///
/// - 4 محافظ افتراضية مع Sender ID + مصدر (SMS / إشعار) + package
/// - بطاقة محفظة: أيقونة ملونة · اسم · محفظة — SENDER · package · شارة · Switch · ⋮
/// - قائمة ⋮: تعديل / إدارة القوالب / حذف
/// - حوار التعديل: معرف المحفظة · اسم · طريقة قراءة الدفع (SMS / إشعارات)
/// - تبويب نقاط البيع: اسم · نقطة بيع — رقم · أيقونة · Switch · ⋮ · FAB وردي
/// - ربط فعلي بـ Domain (WalletCatalog + PosCatalog + PosRegistry)
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
  /// posId → PosAccount (للهاتف والمعرّفات)
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

  // ─── Wallet actions ───────────────────────────────────────────────

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
      _snack((r as Failure).error.message);
    }
    await _load();
  }

  Future<void> _addWallet() async {
    final result = await _editWalletDialog();
    if (result == null || !mounted) return;
    final r = await AppScope.of(context).walletCatalog.saveWallet(
          name: result.name,
          senderId: result.senderId,
          sourceMode: result.mode,
          packageName: result.packageName,
        );
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
    }
    await _load();
  }

  Future<void> _editWallet(Wallet wallet) async {
    final result = await _editWalletDialog(existing: wallet);
    if (result == null || !mounted) return;
    final r = await AppScope.of(context).walletCatalog.updateWallet(
          id: wallet.id,
          name: result.name,
          status: result.status,
          senderId: result.senderId,
          sourceMode: result.mode,
          packageName: result.packageName,
        );
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
    }
    await _load();
  }

  Future<void> _deleteWallet(Wallet wallet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('حذف المحفظة؟', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
          content: Text(
            'سيتم حذف «${wallet.name}» وكل إعداداتها. القوالب المرتبطة تبقى.',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    // Soft-delete via status archived (no hard delete API exposed)
    final r = await AppScope.of(context).walletCatalog.updateWallet(
          id: wallet.id,
          name: wallet.name,
          status: WalletStatus.archived,
          senderId: wallet.senderId,
          sourceMode: wallet.sourceMode,
          packageName: wallet.packageName,
        );
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
    }
    await _load();
  }

  Future<_WalletEditResult?> _editWalletDialog({Wallet? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final senderCtrl = TextEditingController(text: existing?.senderId ?? '');
    final pkgCtrl = TextEditingController(text: existing?.packageName ?? '');
    var mode = existing?.sourceMode ?? WalletSourceMode.sms;
    var status = existing?.status ?? WalletStatus.active;

    return showModalBottomSheet<_WalletEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final bottom = MediaQuery.of(ctx).viewInsets.bottom;
              return Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        existing == null ? 'محفظة جديدة' : 'تعديل محفظة',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('معرف المحفظة (Sender ID)'),
                      TextField(
                        controller: senderCtrl,
                        textAlign: TextAlign.right,
                        decoration: _inputDec(hint: 'JAIB'),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('اسم المحفظة'),
                      TextField(
                        controller: nameCtrl,
                        textAlign: TextAlign.right,
                        decoration: _inputDec(hint: 'جيب'),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                        autofocus: existing == null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'طريقة قراءة الدفع',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _ModeChip(
                              label: 'رسائل SMS',
                              icon: Icons.sms_outlined,
                              selected: mode == WalletSourceMode.sms,
                              onTap: () => setLocal(() => mode = WalletSourceMode.sms),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ModeChip(
                              label: 'الإشعارات',
                              icon: Icons.notifications_active_outlined,
                              selected: mode == WalletSourceMode.notification,
                              onTap: () => setLocal(() => mode = WalletSourceMode.notification),
                            ),
                          ),
                        ],
                      ),
                      if (mode == WalletSourceMode.notification) ...[
                        const SizedBox(height: 14),
                        _fieldLabel('حزمة التطبيق (Package Name)'),
                        TextField(
                          controller: pkgCtrl,
                          textAlign: TextAlign.left,
                          textDirection: TextDirection.ltr,
                          decoration: _inputDec(hint: 'com.ahd.jaib'),
                          style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                        ),
                      ],
                      if (existing != null) ...[
                        const SizedBox(height: 14),
                        _fieldLabel('الحالة'),
                        DropdownButtonFormField<WalletStatus>(
                          value: status,
                          decoration: _inputDec(),
                          items: WalletStatus.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_walletStatusLabel(s),
                                        style: const TextStyle(fontFamily: 'Tajawal')),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => status = v);
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                Navigator.pop(
                                  ctx,
                                  _WalletEditResult(
                                    name: name,
                                    senderId: senderCtrl.text.trim().isEmpty
                                        ? null
                                        : senderCtrl.text.trim(),
                                    mode: mode,
                                    packageName: mode == WalletSourceMode.notification &&
                                            pkgCtrl.text.trim().isNotEmpty
                                        ? pkgCtrl.text.trim()
                                        : null,
                                    status: status,
                                  ),
                                );
                              },
                              child: const Text(
                                'حفظ',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      senderCtrl.dispose();
      pkgCtrl.dispose();
    });
  }

  void _showWalletMenu(Wallet wallet) {
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
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF0F766E)),
                title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _editWallet(wallet);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest_outlined, color: Color(0xFF0F766E)),
                title: const Text('إدارة القوالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
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
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                title: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal', color: Color(0xFFDC2626))),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteWallet(wallet);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── POS actions ──────────────────────────────────────────────────

  Future<void> _togglePos(PointOfSale pos) async {
    final next = pos.status == PointOfSaleStatus.active
        ? PointOfSaleStatus.suspended
        : PointOfSaleStatus.active;
    final r = await AppScope.of(context).posCatalog.updatePointOfSale(
          id: pos.id,
          name: pos.name,
          status: next,
        );
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
    }
    final acc = _posAccounts[pos.id];
    if (acc != null) {
      await AppScope.of(context).posRegistry.save(acc.copyWith(status: next));
    }
    await _load();
  }

  Future<void> _addPos() async {
    final result = await _editPosDialog();
    if (result == null || !mounted) return;
    final c = AppScope.of(context);
    final r = await c.posCatalog.savePointOfSale(name: result.name);
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
      return;
    }
    if (r is Success<PointOfSale>) {
      final pos = r.value;
      final phone = result.phone?.trim();
      final ids = <String>[];
      if (phone != null && phone.isNotEmpty) ids.add(phone);
      await c.posRegistry.save(
        PosAccount(
          posId: pos.id,
          customerId: '',
          name: pos.name,
          identifiers: ids,
          notifyPhone: phone,
          status: pos.status,
          percentageMode: result.percentageMode,
        ),
      );
    }
    await _load();
  }

  Future<void> _editPos(PointOfSale pos) async {
    final c = AppScope.of(context);
    final existingBinding = await c.posRegistry.findByPosId(pos.id);
    PosAccount? prev;
    PosPercentageMode currentMode = PosPercentageMode.defaultCategory;
    String? currentPhone;
    if (existingBinding is Success<PosAccount?> && existingBinding.value != null) {
      prev = existingBinding.value;
      currentMode = prev!.percentageMode;
      currentPhone = prev.notifyPhone ??
          (prev.identifiers.isNotEmpty ? prev.identifiers.first : null);
    }
    final result = await _editPosDialog(
      existing: pos,
      mode: currentMode,
      phone: currentPhone,
    );
    if (result == null || !mounted) return;
    final r = await c.posCatalog.updatePointOfSale(
          id: pos.id,
          name: result.name,
          status: result.status,
        );
    if (r is Failure && mounted) {
      _snack((r as Failure).error.message);
      return;
    }
    final phone = result.phone?.trim();
    final ids = <String>[];
    if (phone != null && phone.isNotEmpty) ids.add(phone);
    if (prev != null) {
      for (final id in prev.identifiers) {
        if (id != phone && !ids.contains(id)) ids.add(id);
      }
    }
    await c.posRegistry.save(
      PosAccount(
        posId: pos.id,
        customerId: prev?.customerId ?? '',
        name: result.name,
        identifiers: ids,
        notifyPhone: phone,
        status: result.status,
        percentageMode: result.percentageMode,
      ),
    );
    await _load();
  }

  Future<_PosEditResult?> _editPosDialog({
    PointOfSale? existing,
    PosPercentageMode mode = PosPercentageMode.defaultCategory,
    String? phone,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: phone ?? '');
    var status = existing?.status ?? PointOfSaleStatus.active;
    var percentageMode = mode;

    return showModalBottomSheet<_PosEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final bottom = MediaQuery.of(ctx).viewInsets.bottom;
              return Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        existing == null ? 'نقطة بيع جديدة' : 'تعديل نقطة البيع',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('اسم نقطة البيع'),
                      TextField(
                        controller: nameCtrl,
                        textAlign: TextAlign.right,
                        decoration: _inputDec(hint: 'بقاله كيان'),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                        autofocus: true,
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('رقم الهاتف / GSM'),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        decoration: _inputDec(hint: '77xxxxxxx'),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('وضع نسبة العمولة'),
                      DropdownButtonFormField<PosPercentageMode>(
                        value: percentageMode,
                        decoration: _inputDec(),
                        items: const [
                          DropdownMenuItem(
                            value: PosPercentageMode.defaultCategory,
                            child: Text('نسبة الفئة الافتراضية',
                                style: TextStyle(fontFamily: 'Tajawal')),
                          ),
                          DropdownMenuItem(
                            value: PosPercentageMode.zero,
                            child: Text('عمولة صفرية (0%)',
                                style: TextStyle(fontFamily: 'Tajawal')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => percentageMode = v);
                        },
                      ),
                      if (existing != null) ...[
                        const SizedBox(height: 14),
                        _fieldLabel('الحالة'),
                        DropdownButtonFormField<PointOfSaleStatus>(
                          value: status,
                          decoration: _inputDec(),
                          items: PointOfSaleStatus.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_posStatusLabel(s),
                                        style: const TextStyle(fontFamily: 'Tajawal')),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => status = v);
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                Navigator.pop(
                                  ctx,
                                  _PosEditResult(
                                    name: name,
                                    phone: phoneCtrl.text.trim().isEmpty
                                        ? null
                                        : phoneCtrl.text.trim(),
                                    status: status,
                                    percentageMode: percentageMode,
                                  ),
                                );
                              },
                              child: const Text(
                                'حفظ',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    });
  }

  void _showPosMenu(PointOfSale pos) {
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
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF0F766E)),
                title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _editPos(pos);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest_outlined, color: Color(0xFF0F766E)),
                title: const Text('إدارة القوالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TemplatesScreen(
                        posAccountId: pos.id,
                        posName: pos.name,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                title: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal', color: Color(0xFFDC2626))),
                onTap: () async {
                  Navigator.pop(ctx);
                  final r = await AppScope.of(context).posCatalog.updatePointOfSale(
                        id: pos.id,
                        name: pos.name,
                        status: PointOfSaleStatus.archived,
                      );
                  if (r is Failure && mounted) {
                    _snack((r as Failure).error.message);
                  }
                  await _load();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward, color: Color(0xFF334155)),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'إدارة المحافظ ونقاط البيع',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'إعداد وتفعيل المحافظ ونقاط البيع المرتبطة بالرسائل',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
              onPressed: () {},
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _tabs.index == 0 ? _addWallet : _addPos,
          backgroundColor: const Color(0xFFA855F7),
          foregroundColor: Colors.white,
          elevation: 3,
          icon: const Icon(Icons.add, size: 22),
          label: Text(
            _tabs.index == 0 ? 'محفظة جديدة' : 'إضافة نقطة بيع',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        body: Column(
          children: [
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو المعرف...',
                  hintStyle: const TextStyle(fontFamily: 'Tajawal', color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                  ),
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
            ),
            // Tabs
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                labelColor: const Color(0xFF0F766E),
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                indicatorColor: const Color(0xFF0F766E),
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'المحافظ'),
                  Tab(text: 'نقاط البيع'),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const AsyncLoadingView()
                  : _error != null
                      ? AsyncErrorView(message: _error!, onRetry: _load)
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _walletsList(),
                            _posList(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletsList() {
    final items = _filteredWallets
        .where((w) => w.status != WalletStatus.archived)
        .toList();
    if (items.isEmpty) {
      return AsyncEmptyView(
        message: 'لا توجد محافظ',
        actionLabel: 'إضافة محفظة',
        onAction: _addWallet,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF0F766E),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final w = items[i];
          return _WalletCard(
            wallet: w,
            brandColor: _colorFor(w),
            onToggle: () => _toggleWallet(w),
            onMenu: () => _showWalletMenu(w),
          );
        },
      ),
    );
  }

  Widget _posList() {
    final items = _filteredPos
        .where((p) => p.status != PointOfSaleStatus.archived)
        .toList();
    if (items.isEmpty) {
      return AsyncEmptyView(
        message: 'لا توجد نقاط بيع',
        actionLabel: 'إضافة نقطة بيع',
        onAction: _addPos,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF0F766E),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = items[i];
          final acc = _posAccounts[p.id];
          final phone = acc?.notifyPhone ??
              (acc != null && acc.identifiers.isNotEmpty
                  ? acc.identifiers.first
                  : null);
          return _PosCard(
            pos: p,
            phone: phone,
            onToggle: () => _togglePos(p),
            onMenu: () => _showPosMenu(p),
          );
        },
      ),
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
      );

  InputDecoration _inputDec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Tajawal', color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
        ),
      );
}

// ─── Models ─────────────────────────────────────────────────────────

class _WalletEditResult {
  const _WalletEditResult({
    required this.name,
    required this.senderId,
    required this.mode,
    required this.packageName,
    required this.status,
  });
  final String name;
  final String? senderId;
  final WalletSourceMode mode;
  final String? packageName;
  final WalletStatus status;
}

class _PosEditResult {
  const _PosEditResult({
    required this.name,
    required this.phone,
    required this.status,
    required this.percentageMode,
  });
  final String name;
  final String? phone;
  final PointOfSaleStatus status;
  final PosPercentageMode percentageMode;
}

// ─── Wallet Card (video-accurate) ───────────────────────────────────

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.brandColor,
    required this.onToggle,
    required this.onMenu,
  });

  final Wallet wallet;
  final Color brandColor;
  final VoidCallback onToggle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final isActive = wallet.status == WalletStatus.active;
    final isNotif = wallet.sourceMode == WalletSourceMode.notification;
    final sender = wallet.senderId?.isNotEmpty == true ? wallet.senderId! : '—';

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // ⋮ menu (left in RTL visual = start)
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF94A3B8)),
                onPressed: onMenu,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              // Switch
              Switch.adaptive(
                value: isActive,
                activeColor: const Color(0xFF0F766E),
                onChanged: (_) => onToggle(),
              ),
              const SizedBox(width: 4),
              // Mode badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isNotif
                      ? const Color(0xFFF3E8FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isNotif ? Icons.notifications_active_outlined : Icons.sms_outlined,
                      size: 13,
                      color: isNotif ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isNotif ? 'إشعار' : 'SMS',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isNotif ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Texts (name + محفظة — SENDER + package)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      wallet.name,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'محفظة — $sender',
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (isNotif &&
                        wallet.packageName != null &&
                        wallet.packageName!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        wallet.packageName!,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Brand icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brandColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: brandColor,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── POS Card (video-accurate) ──────────────────────────────────────

class _PosCard extends StatelessWidget {
  const _PosCard({
    required this.pos,
    required this.phone,
    required this.onToggle,
    required this.onMenu,
  });

  final PointOfSale pos;
  final String? phone;
  final VoidCallback onToggle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final isActive = pos.status == PointOfSaleStatus.active;
    final phoneLabel = (phone != null && phone!.isNotEmpty) ? phone! : '—';

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF94A3B8)),
                onPressed: onMenu,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Switch.adaptive(
                value: isActive,
                activeColor: const Color(0xFF0F766E),
                onChanged: (_) => onToggle(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pos.name,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'نقطة بيع — $phoneLabel',
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Color(0xFF0F766E),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mode chip (SMS / Notifications) ────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFCCFBF1) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected)
                const Icon(Icons.check, size: 16, color: Color(0xFF0F766E)),
              if (selected) const SizedBox(width: 4),
              Icon(
                icon,
                size: 16,
                color: selected ? const Color(0xFF0F766E) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                ),
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
