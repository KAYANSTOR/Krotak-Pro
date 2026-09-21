import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/wallet.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import 'settings/templates_screen.dart';

/// إدارة المحافظ — **منفصلة عن نقاط البيع** (انظر `PosScreen`).
///
/// كل محفظة لها: حالة (نشط/موقوف)، طريقة قراءة الدفع (رسائل SMS أو إشعارات
/// تطبيق)، وكتالوج قوالب استخراج البيانات الخاص بها. كانت نقاط البيع تبويباً
/// في هذه الشاشة فأصبحت شاشة مستقلة.
class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<Wallet> _wallets = const [];
  Set<String> _togglingIds = {};

  static const _brandColors = <String, Color>{
    'جيب': Color(0xFF0EA5E9),
    'جوالي': Color(0xFF8B5CF6),
    'ون كاش': Color(0xFFF59E0B),
    'فلوسك': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppScope.of(context).walletCatalog.ensureDefaultWallets();
      await _load();
    });
  }

  @override
  void dispose() {
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
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (wallets is Failure) {
        _error = (wallets as Failure).error.message;
        return;
      }
      _wallets = (wallets as Success<List<Wallet>>).value;
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

    final c = AppScope.of(context);
    if (existing == null) {
      final r = await c.walletCatalog.saveWallet(
            name: name,
            senderId: sender.isEmpty ? null : sender,
            sourceMode: mode,
            packageName: mode == WalletSourceMode.notification && pkg.isNotEmpty ? pkg : null,
          );
      if (r is Failure && mounted) {
        _snack((r as Failure).error.message);
        return;
      }
    } else {
      final r = await c.walletCatalog.updateWallet(
            id: existing.id,
            name: name,
            status: existing.status,
            senderId: sender.isEmpty ? null : sender,
            sourceMode: mode,
            packageName: mode == WalletSourceMode.notification && pkg.isNotEmpty ? pkg : null,
          );
      if (r is Failure && mounted) {
        _snack((r as Failure).error.message);
        return;
      }
    }

    // تفعيل مصدر الإشعار فعلياً عند اختيار وضع الإشعارات + package.
    if (mode == WalletSourceMode.notification && pkg.isNotEmpty) {
      final reg = await c.notificationSources.upsert(
        displayName: name,
        packageName: pkg,
        enabled: true,
      );
      if (reg is Failure && mounted) {
        _snack('حُفظت المحفظة لكن تعذّر تفعيل مصدر الإشعار: ${(reg as Failure).error.message}');
      } else if (mounted) {
        final granted = await c.notificationBridge.isAccessGranted();
        if (!granted) {
          _snack('فعّل إذن وصول الإشعارات لكروتك الآن');
          await c.notificationBridge.openAccessSettings();
        } else {
          _snack('تم تفعيل قراءة إشعارات «$name»');
        }
      }
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
              Text('إدارة المحافظ',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 17)),
              Text('إعداد وتفعيل المحافظ المرتبطة برسائل الدفع',
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
                      Expanded(child: _walletsList()),
                    ],
                  ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: KayanColors.accentPink,
          shape: const StadiumBorder(),
          onPressed: () => _editWallet(null),
          icon: const Icon(Icons.add),
          label: const Text(
            'إضافة محفظة',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
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
}
