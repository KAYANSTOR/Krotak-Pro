import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../../platform/contact_picker_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

/// إدارة المحافظ ونقاط البيع — مطابقة فيديو المنتج + مفتاح تفعيل فعّال.
class WalletsPosScreen extends StatefulWidget {
  const WalletsPosScreen({super.key, this.focusPosId});

  final String? focusPosId;

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
  bool _showArchivedPos = false;
  bool _focusHandled = false;

  static const _brandColors = <String, Color>{
    'جيب': Color(0xFF0EA5E9),
    'جوالي': Color(0xFF8B5CF6),
    'ون كاش': Color(0xFFF59E0B),
    'فلوسك': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.focusPosId != null ? 1 : 0);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
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
    final profiles = await c.posProfiles.listPointOfSaleProfiles(
      includeArchived: true,
    );

    if (!mounted) return;
    if (wallets is Failure) {
      setState(() {
        _loading = false;
        _error = (wallets as Failure).error.message;
      });
      return;
    }
    if (profiles is Failure) {
      setState(() {
        _loading = false;
        _error = (profiles as Failure).error.message;
      });
      return;
    }

    final profileList = (profiles as Success<List<PointOfSaleProfile>>).value;
    final nextAccounts = <String, PosAccount>{};
    for (final profile in profileList) {
      final account = profile.account;
      if (account != null) {
        nextAccounts[profile.pointOfSale.id] = account;
      }
    }

    setState(() {
      _loading = false;
      _wallets = (wallets as Success<List<Wallet>>).value;
      _pos = [for (final profile in profileList) profile.pointOfSale];
      _posAccounts = nextAccounts;
    });

    final focusId = widget.focusPosId;
    if (!_focusHandled && focusId != null && mounted) {
      final target = _pos.where((p) => p.id == focusId).firstOrNull;
      if (target != null) {
        _focusHandled = true;
        _showArchivedPos = target.status == PointOfSaleStatus.archived;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _tabs.animateTo(1);
          await _editPos(target);
        });
      }
    }
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
      final s = {..._togglingIds}..remove(wallet.id);
      _togglingIds = s;
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
    if (_togglingIds.contains(pos.id) ||
        pos.status == PointOfSaleStatus.archived) return;

    final next = pos.status == PointOfSaleStatus.active
        ? PointOfSaleStatus.suspended
        : PointOfSaleStatus.active;

    setState(() {
      _togglingIds = {..._togglingIds, pos.id};
    });

    final r = await AppScope.of(context).posProfiles.setPointOfSaleStatus(
      id: pos.id,
      status: next,
    );

    if (!mounted) return;
    setState(() {
      final s = {..._togglingIds}..remove(pos.id);
      _togglingIds = s;
    });

    if (r is Failure) {
      _snack((r as Failure).error.message);
      await _load();
      return;
    }

    _snack(
      next == PointOfSaleStatus.active
          ? 'تم تفعيل نقطة البيع «${pos.name}»'
          : 'تم إيقاف نقطة البيع «${pos.name}»',
    );
    await _load();
  }

  Future<void> _editWallet(Wallet? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final senderCtrl = TextEditingController(text: existing?.senderId ?? '');
    final pkgCtrl = TextEditingController(text: existing?.packageName ?? '');
    var mode = existing?.sourceMode ?? WalletSourceMode.sms;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final inset = MediaQuery.viewInsetsOf(ctx).bottom;
              return Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
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
                            color: KayanPalette.of(ctx).border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        existing == null ? 'محفظة جديدة' : 'تعديل محفظة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: context.kayan.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: senderCtrl,
                        decoration: const InputDecoration(
                          labelText: 'معرف المحفظة (Sender ID)',
                          hintText: 'JAIB',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم المحفظة',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      const Text('طريقة قراءة الدفع',
                          style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('رسائل SMS', style: TextStyle(fontFamily: 'Tajawal')),
                              selected: mode == WalletSourceMode.sms,
                              onSelected: (_) => setLocal(() => mode = WalletSourceMode.sms),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('الإشعارات', style: TextStyle(fontFamily: 'Tajawal')),
                              selected: mode == WalletSourceMode.notification,
                              onSelected: (_) =>
                                  setLocal(() => mode = WalletSourceMode.notification),
                            ),
                          ),
                        ],
                      ),
                      if (mode == WalletSourceMode.notification) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: pkgCtrl,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'اسم حزمة التطبيق (Package Name)',
                            hintText: 'com.ahd.jaib',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              onPressed: () {
                                if (nameCtrl.text.trim().isEmpty) return;
                                Navigator.pop(ctx, true);
                              },
                              child: Text(
                                existing == null ? 'إنشاء' : 'حفظ',
                                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
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
    );

    if (ok != true || !mounted) {
      nameCtrl.dispose();
      senderCtrl.dispose();
      pkgCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    final sender = senderCtrl.text.trim();
    final pkg = pkgCtrl.text.trim();
    nameCtrl.dispose();
    senderCtrl.dispose();
    pkgCtrl.dispose();

    if (existing == null) {
      final r = await AppScope.of(context).walletCatalog.saveWallet(
            name: name,
            senderId: sender.isEmpty ? null : sender,
            sourceMode: mode,
            packageName: mode == WalletSourceMode.notification && pkg.isNotEmpty ? pkg : null,
          );
      if (r is Failure && mounted) _snack((r as Failure).error.message);
    } else {
      final r = await AppScope.of(context).walletCatalog.updateWallet(
            id: existing.id,
            name: name,
            status: existing.status,
            senderId: sender.isEmpty ? null : sender,
            sourceMode: mode,
            packageName: mode == WalletSourceMode.notification && pkg.isNotEmpty ? pkg : null,
          );
      if (r is Failure && mounted) _snack((r as Failure).error.message);
    }
    await _load();
  }

  void _walletMenu(Wallet w) {
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
              ListTile(
                leading: Icon(Icons.edit_outlined, color: context.kayan.primary),
                title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _editWallet(w);
                },
              ),
              ListTile(
                leading: Icon(Icons.settings_suggest_outlined, color: context.kayan.primary),
                title: const Text('إدارة القوالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TemplatesScreen(walletId: w.id, walletName: w.name),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: context.netColors.rejected,
                ),
                title: Text(
                  'حذف',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    color: context.netColors.rejected,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final r = await AppScope.of(context).walletCatalog.updateWallet(
                        id: w.id,
                        name: w.name,
                        status: WalletStatus.archived,
                        senderId: w.senderId,
                        sourceMode: w.sourceMode,
                        packageName: w.packageName,
                      );
                  if (r is Failure && mounted) _snack((r as Failure).error.message);
                  await _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPos(PointOfSale? existing) async {
    final acc = existing != null ? _posAccounts[existing.id] : null;
    final phoneCtrl = TextEditingController(
      text: acc?.notifyPhone ??
          (acc != null && acc.identifiers.isNotEmpty
              ? acc.identifiers.first
              : ''),
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final limitCtrl = TextEditingController(
      text: acc?.creditLimitMinorUnits == null
          ? '50000'
          : (acc!.creditLimitMinorUnits! ~/ 100).toString(),
    );
    var mode = acc?.percentageMode ?? PosPercentageMode.defaultCategory;
    var saving = false;
    String? formError;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final inset = MediaQuery.viewInsetsOf(ctx).bottom;
            final palette = KayanPalette.of(ctx);
            return Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        existing == null ? 'نقطة بيع جديدة' : 'تعديل نقطة البيع',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: palette.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم جوال نقطة البيع',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم نقطة البيع',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: limitCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سقف الدين المسموح به (ر.ي)',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'نسبة نقطة البيع',
                        style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                      ),
                      RadioListTile<PosPercentageMode>(
                        contentPadding: EdgeInsets.zero,
                        value: PosPercentageMode.defaultCategory,
                        groupValue: mode,
                        onChanged: (v) => setLocal(() => mode = v ?? mode),
                        title: const Text(
                          'النسبة الافتراضية لفئات الكروت',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                      RadioListTile<PosPercentageMode>(
                        contentPadding: EdgeInsets.zero,
                        value: PosPercentageMode.zero,
                        groupValue: mode,
                        onChanged: (v) => setLocal(() => mode = v ?? mode),
                        title: const Text(
                          '0% — بدون عمولة',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          formError!,
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            color: context.netColors.rejected,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: saving ? null : () => Navigator.pop(ctx, false),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final name = nameCtrl.text.trim();
                                      final phone = phoneCtrl.text.trim();
                                      final creditRial = int.tryParse(limitCtrl.text.trim());

                                      if (name.isEmpty) {
                                        setLocal(() => formError = 'أدخل اسم نقطة البيع');
                                        return;
                                      }
                                      if (creditRial != null && creditRial < 0) {
                                        setLocal(() => formError = 'سقف الدين لا يمكن أن يكون سالباً');
                                        return;
                                      }

                                      setLocal(() {
                                        saving = true;
                                        formError = null;
                                      });

                                      final result = existing == null
                                          ? await AppScope.of(context).posProfiles.createPointOfSaleProfile(
                                              name: name,
                                              phone: phone,
                                              creditLimitMinorUnits:
                                                  creditRial == null ? null : creditRial * 100,
                                              percentageMode: mode,
                                            )
                                          : await AppScope.of(context).posProfiles.updatePointOfSaleProfile(
                                              id: existing.id,
                                              name: name,
                                              phone: phone,
                                              creditLimitMinorUnits:
                                                  creditRial == null ? null : creditRial * 100,
                                              percentageMode: mode,
                                              status: existing.status,
                                            );

                                      if (!mounted) return;
                                      if (result is Failure) {
                                        setLocal(() {
                                          saving = false;
                                          formError = (result as Failure).error.message;
                                        });
                                        return;
                                      }
                                      Navigator.pop(ctx, true);
                                    },
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(
                                      existing == null
                                          ? 'إنشاء نقطة البيع'
                                          : 'حفظ التعديلات',
                                      style: const TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final createdName = nameCtrl.text.trim();
    phoneCtrl.dispose();
    nameCtrl.dispose();
    limitCtrl.dispose();

    if (ok != true || !mounted) return;

    final container = AppScope.of(context);
    await container.reloadTemplates();
    await _load();

    if (existing == null && mounted) {
      final profiles = await container.posProfiles.listPointOfSaleProfiles(
        includeArchived: true,
      );
      if (profiles is Success<List<PointOfSaleProfile>>) {
        final created = profiles.value.where(
          (p) => p.pointOfSale.name == createdName,
        ).firstOrNull;
        if (created != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TemplatesScreen(
                posId: created.pointOfSale.id,
                posName: created.pointOfSale.name,
              ),
            ),
          );
        }
      }
    }
  }

  void _posMenu(PointOfSale p) {
    final archived = p.status == PointOfSaleStatus.archived;
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
              if (!archived)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: context.kayan.primary),
                  title: const Text(
                    'تعديل بيانات نقطة البيع',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editPos(p);
                  },
                ),
              ListTile(
                leading: Icon(Icons.settings_suggest_outlined, color: context.kayan.primary),
                title: const Text(
                  'إدارة القوالب',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TemplatesScreen(posId: p.id, posName: p.name),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  color: archived ? context.kayan.primary : context.netColors.rejected,
                ),
                title: Text(
                  archived ? 'استعادة نقطة البيع' : 'أرشفة نقطة البيع',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    color: archived ? context.kayan.primary : context.netColors.rejected,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final r = archived
                      ? await AppScope.of(context).posProfiles.setPointOfSaleStatus(
                          id: p.id,
                          status: PointOfSaleStatus.active,
                        )
                      : await AppScope.of(context).posProfiles.archivePointOfSale(p.id);
                  if (r is Failure && mounted) {
                    _snack((r as Failure).error.message);
                  } else if (mounted) {
                    _snack(
                      archived
                          ? 'تمت استعادة نقطة البيع «${p.name}»'
                          : 'تمت أرشفة نقطة البيع «${p.name}»',
                    );
                  }
                  await _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إدارة المحافظ ونقاط البيع',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 17)),
              Text('إعداد وتفعيل المحافظ ونقاط البيع المرتبطة بالرسائل',
                  style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
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
                            hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
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
                        labelColor: context.kayan.primary,
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
          backgroundColor: KayanColors.accentPink,
          shape: const StadiumBorder(),
          onPressed: () {
            if (_tabs.index == 0) {
              _editWallet(null);
            } else {
              _editPos(null);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(
            _tabs.index == 0 ? 'إضافة محفظة' : 'إضافة نقطة بيع',
            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _walletsList() {
    final items = _filteredWallets.where((w) => w.status != WalletStatus.archived).toList();
    if (items.isEmpty) {
      return AsyncEmptyView(
        message: 'لا توجد محافظ',
        actionLabel: 'إضافة محفظة',
        onAction: () => _editWallet(null),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: context.kayan.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final w = items[i];
          final active = w.status == WalletStatus.active;
          final color = _colorFor(w);
          final isNotif = w.sourceMode == WalletSourceMode.notification;
          return Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => _walletMenu(w),
                  ),
                  Switch.adaptive(
                    value: active,
                    activeColor: context.kayan.primary,
                    onChanged: _togglingIds.contains(w.id) ? null : (_) => _toggleWallet(w),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isNotif
                          ? context.netColors.soldContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isNotif ? 'إشعار' : 'SMS',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isNotif
                            ? context.netColors.sold
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.name,
                            style: const TextStyle(
                                fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(
                          'محفظة — ${w.senderId ?? '—'}',
                          style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        if (w.packageName != null && w.packageName!.isNotEmpty)
                          Text(
                            w.packageName!,
                            style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant),
                            textDirection: TextDirection.ltr,
                          ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text(
                      w.name.isNotEmpty ? w.name.characters.first : '?',
                      style: TextStyle(
                          fontFamily: 'Tajawal', fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _posList() {
    final all = _filteredPos;
    final active = all.where((p) => p.status == PointOfSaleStatus.active).length;
    final suspended = all.where((p) => p.status == PointOfSaleStatus.suspended).length;
    final archived = all.where((p) => p.status == PointOfSaleStatus.archived).length;

    final items = all
        .where((p) => _showArchivedPos || p.status != PointOfSaleStatus.archived)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$active نشطة · $suspended موقوفة · $archived مؤرشفة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilterChip(
                selected: _showArchivedPos,
                label: const Text(
                  'عرض المؤرشفة',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 11),
                ),
                onSelected: (value) => setState(() => _showArchivedPos = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            AsyncEmptyView(
              message: _showArchivedPos && archived > 0
                  ? 'لا توجد نتائج مطابقة'
                  : 'لا توجد نقاط بيع نشطة أو موقوفة',
              actionLabel: 'إضافة نقطة بيع',
              onAction: () => _editPos(null),
            )
          else
            ...items.map((p) {
              final acc = _posAccounts[p.id];
              final phone = acc?.notifyPhone ??
                  (acc != null && acc.identifiers.isNotEmpty
                      ? acc.identifiers.first
                      : null);
              final isArchived = p.status == PointOfSaleStatus.archived;
              final activeState = p.status == PointOfSaleStatus.active;
              return Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => _posMenu(p),
                      ),
                      if (!isArchived)
                        Switch.adaptive(
                          value: activeState,
                          activeColor: context.kayan.primary,
                          onChanged: _togglingIds.contains(p.id)
                              ? null
                              : (_) => _togglePos(p),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'مؤرشف',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.netColors.rejected,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              phone == null ? 'نقطة بيع' : 'نقطة بيع — $phone',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (acc == null)
                              Text(
                                'بيانات الحساب غير مكتملة',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: context.netColors.warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        isArchived
                            ? Icons.inventory_2_outlined
                            : Icons.storefront_outlined,
                        color: context.kayan.primary,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }


}
