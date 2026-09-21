import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/services/local_pos_profile_service.dart';
import '../../domain/services/local_transfer_template_activation_service.dart';
import '../../platform/contact_picker_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/pos/pos_customer_link_dialog.dart';
import 'settings/templates_screen.dart';

/// شاشة نقاط البيع — **منفصلة عن إدارة المحافظ**.
///
/// كانت نقاط البيع تبويباً داخل «إدارة المحافظ ونقاط البيع»، فأصبح المشغّل
/// يمر بمحافظ لا يحتاجها للوصول إليها. هنا شاشة مستقلة:
/// إنشاء/تعديل نقطة بيع، سقف الدين والنسبة، حالة الاستقبال، وحالة القوالب.
///
/// حالة القوالب معروضة لكل نقطة (نشط من الإجمالي) لأن نقطة البيع الواحدة
/// تحتاج **عدة قوالب نشطة معاً** (طلب كرت، عدة كروت، رقم تسليم، طلب رصيد) —
/// وكتالوج القوالب يكتمل تلقائياً عند فتح الشاشة (إضافة الناقص فقط دون المساس
/// بحالة أو نصوص القوالب الموجودة).
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<PointOfSale> _pos = const [];
  Map<String, PosAccount> _accounts = const {};

  /// حالة قوالب كل نقطة بيع: (النشط، الإجمالي).
  Map<String, ({int active, int total})> _templateCounts = const {};
  Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    final posList = await c.pointsOfSale.listAll();
    if (posList is Failure<List<PointOfSale>>) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = posList.error.message;
      });
      return;
    }
    final points = (posList as Success<List<PointOfSale>>).value;

    final accounts = <String, PosAccount>{};
    for (final p in points) {
      final r = await c.posRegistry.findByPosId(p.id);
      if (r is Success<PosAccount?> && r.value != null) {
        accounts[p.id] = r.value!;
      }
    }

    // إكمال كتالوج القوالب لنقاط البيع القائمة (المراحل السابقة قد تكون زُرعت
    // بكتالوج ناقص). إضافة الناقص فقط: لا تُفعّل قالباً أوقفه المشغّل.
    var added = 0;
    for (final p in points.where((p) => p.status != PointOfSaleStatus.archived)) {
      final r = await c.posProfile.ensureInboundTemplates(posId: p.id, posName: p.name);
      if (r is Success<int>) added += r.value;
    }
    if (added > 0) await c.reloadTemplates();

    final counts = await _readCounts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _pos = points;
      _accounts = accounts;
      _templateCounts = counts;
    });
  }

  /// يقرأ حالة القوالب لكل نقطة بيع من القوالب المحمّلة (قراءة واحدة).
  Future<Map<String, ({int active, int total})>> _readCounts() async {
    final c = AppScope.of(context);
    final all = await c.transferTemplates.listAll();
    final counts = <String, ({int active, int total})>{};
    if (all is Success<List<TransferTemplate>>) {
      for (final t in all.value) {
        final posId = t.posId?.trim();
        if (posId == null || posId.isEmpty) continue;
        final current = counts[posId] ?? (active: 0, total: 0);
        counts[posId] = (
          active: current.active + (t.isActive ? 1 : 0),
          total: current.total + 1,
        );
      }
    }
    return counts;
  }

  List<PointOfSale> get _filtered {
    final open = _pos.where((p) => p.status != PointOfSaleStatus.archived).toList();
    if (_query.isEmpty) return open;
    final q = _query.toLowerCase();
    return open.where((p) {
      if (p.name.toLowerCase().contains(q)) return true;
      final acc = _accounts[p.id];
      if (acc == null) return false;
      if ((acc.notifyPhone ?? '').contains(q)) return true;
      return acc.identifiers.any((id) => id.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _togglePos(PointOfSale pos) async {
    if (_busy.contains(pos.id)) return;
    final next = pos.status == PointOfSaleStatus.active
        ? PointOfSaleStatus.suspended
        : PointOfSaleStatus.active;
    final previous = pos.status;
    setState(() {
      _busy = {..._busy, pos.id};
      _pos = [
        for (final p in _pos)
          if (p.id == pos.id)
            PointOfSale(id: p.id, name: p.name, status: next, createdAt: p.createdAt)
          else
            p,
      ];
    });
    final c = AppScope.of(context);
    final r = await c.posCatalog.updatePointOfSale(
      id: pos.id,
      name: pos.name,
      status: next,
    );
    if (!mounted) return;
    if (r is Success) {
      final acc = _accounts[pos.id];
      if (acc != null) {
        await c.posRegistry.save(acc.copyWith(status: next));
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = {..._busy}..remove(pos.id);
      if (r is Failure) {
        _pos = [
          for (final p in _pos)
            if (p.id == pos.id)
              PointOfSale(id: p.id, name: p.name, status: previous, createdAt: p.createdAt)
            else
              p,
        ];
      }
    });
    if (r is Failure) {
      _snack((r as Failure).error.message);
      return;
    }
    _snack(next == PointOfSaleStatus.active
        ? 'تم تفعيل نقطة البيع «${pos.name}» — سيتعرف النظام على رسائلها'
        : 'تم إيقاف نقطة البيع «${pos.name}» — لن تُعالج رسائلها');
  }

  /// تفعيل/إيقاف كل قوالب نقطة بيع واحدة بضغطة (بدل قالب واحد فقط).
  Future<void> _setAllTemplates(PointOfSale pos, bool isActive) async {
    setState(() => _busy = {..._busy, pos.id});
    final c = AppScope.of(context);
    final r = await LocalTransferTemplateActivationService(c.transferTemplates)
        .setGroupActive(key: 'pos:${pos.id}', isActive: isActive);
    if (r is Success<int> && r.value > 0) {
      await c.reloadTemplates();
    }
    if (!mounted) return;
    final counts = await _readCounts();
    if (!mounted) return;
    setState(() {
      _busy = {..._busy}..remove(pos.id);
      _templateCounts = counts;
    });
    if (r is Failure) {
      _snack(r.error.message);
      return;
    }
    final changed = (r as Success<int>).value;
    _snack(
      changed == 0
          ? (isActive ? 'كل قوالب «${pos.name}» مفعّلة بالفعل' : 'كل قوالب «${pos.name}» متوقفة بالفعل')
          : (isActive
              ? 'تم تفعيل $changed قالباً لـ«${pos.name}» — يستجيب النظام لكل صيغ الرسائل'
              : 'تم إيقاف $changed قالباً لـ«${pos.name}»'),
    );
  }

  Future<void> _editPos(PointOfSale? existing) async {
    final acc = existing != null ? _accounts[existing.id] : null;
    final phoneCtrl = TextEditingController(
      text: acc?.notifyPhone ??
          (acc != null && acc.identifiers.isNotEmpty ? acc.identifiers.first : ''),
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final creditCtrl = TextEditingController(
      text: existing == null
          ? '50000'
          : (acc?.creditLimitMinorUnits != null
              ? (acc!.creditLimitMinorUnits! ~/ 100).toString()
              : ''),
    );
    var mode = acc?.percentageMode ?? PosPercentageMode.defaultCategory;
    final contactPicker = ContactPickerBridge();
    var picking = false;
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
                      const SizedBox(height: 6),
                      Text(
                        existing == null
                            ? 'سيتم إنشاء كتالوج قوالب كامل ومفعّل تلقائياً لهذه النقطة'
                            : 'أي استعلام عن رصيد نقطة البيع يعتمد على هذا الرقم',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم جوال نقطة البيع',
                          prefixIcon: IconButton(
                            icon: picking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.contact_phone_outlined),
                            onPressed: picking
                                ? null
                                : () async {
                                    setLocal(() => picking = true);
                                    final phone = await contactPicker.pickPhone();
                                    if (!mounted) return;
                                    setLocal(() => picking = false);
                                    if (phone != null && phone.isNotEmpty) {
                                      phoneCtrl.text = phone;
                                      phoneCtrl.selection =
                                          TextSelection.collapsed(offset: phone.length);
                                    }
                                  },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'إسم نقطة البيع',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: creditCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سقف الدين المسموح به (ر.ي)',
                          helperText: 'اتركه فارغاً لبلا سقف',
                          helperStyle: TextStyle(fontFamily: 'Tajawal'),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'نسبة نقطة البيع',
                        style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                      ),
                      RadioListTile<PosPercentageMode>(
                        contentPadding: EdgeInsets.zero,
                        value: PosPercentageMode.defaultCategory,
                        groupValue: mode,
                        activeColor: context.kayan.primary,
                        onChanged: (v) => setLocal(() => mode = v!),
                        title: Text(
                          existing == null
                              ? 'إنشاء نقطة البيع بالنسبة الافتراضية'
                              : 'النسبة الافتراضية لفئات الكروت',
                          style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'استخدام نسب الخصم المحددة مسبقاً لكل فئة كروت',
                          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                        ),
                      ),
                      RadioListTile<PosPercentageMode>(
                        contentPadding: EdgeInsets.zero,
                        value: PosPercentageMode.zero,
                        groupValue: mode,
                        activeColor: context.kayan.primary,
                        onChanged: (v) => setLocal(() => mode = v!),
                        title: Text(
                          existing == null
                              ? 'إنشاء نقطة البيع بنسبة صفر'
                              : 'نسبة صفر لجميع الفئات (0%)',
                          style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'تطبيق نسبة خصم 0% لجميع فئات الكروت لنقطة البيع هذه',
                          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                        ),
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.netColors.rejected.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context.netColors.rejected.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            formError!,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12.5,
                              color: context.netColors.rejected,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
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
                                backgroundColor: context.kayan.primary,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final name = nameCtrl.text.trim();
                                      final phone = phoneCtrl.text.trim();
                                      if (name.isEmpty) {
                                        setLocal(() => formError = 'أدخل اسم نقطة البيع');
                                        return;
                                      }
                                      if (phone.isEmpty) {
                                        setLocal(() => formError = 'أدخل رقم جوال نقطة البيع');
                                        return;
                                      }
                                      setLocal(() {
                                        saving = true;
                                        formError = null;
                                      });
                                      final c = AppScope.of(context);
                                      final problem = await c.posProfile.validate(
                                        name: name,
                                        phone: phone,
                                        existingPosId: existing?.id,
                                        existingCustomerId: acc?.customerId,
                                        allowExistingCustomer: existing == null,
                                      );
                                      if (!mounted) return;
                                      if (problem != null) {
                                        setLocal(() {
                                          saving = false;
                                          formError = problem;
                                        });
                                        return;
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx, true);
                                    },
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      existing == null ? 'إنشاء' : 'حفظ',
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

    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final creditRial = int.tryParse(creditCtrl.text.trim()) ?? 0;
    final creditMinor = creditRial > 0 ? creditRial * 100 : null;
    phoneCtrl.dispose();
    nameCtrl.dispose();
    creditCtrl.dispose();
    if (ok != true || !mounted) return;

    final c = AppScope.of(context);

    if (existing == null) {
      // الرقم قد يكون مسجّلاً لعميل قائم: نقطة البيع لا تملك دفتراً مالياً
      // مستقلاً، فيُربط الحساب نفسه بعد تأكيد صريح بدل الرفض.
      final linkable = await c.posProfile.linkableCustomer(phone);
      if (!mounted) return;
      final foundCustomer = linkable is Success<Customer?> ? linkable.value : null;
      if (foundCustomer != null) {
        final confirmed = await confirmLinkPosToCustomer(
          context: context,
          customerName: foundCustomer.displayName,
          phone: phone,
        );
        if (!mounted) return;
        if (!confirmed) {
          _snack('لم يتم الإنشاء — الرقم مسجّل كعميل قائم');
          return;
        }
      }
      final created = await c.posProfile.create(
        name: name,
        phone: phone,
        percentageMode: mode,
        creditLimitMinorUnits: creditMinor,
      );
      if (!mounted) return;
      if (created is Failure<PosProfile>) {
        _snack(created.error.message);
        return;
      }
      final pos = (created as Success<PosProfile>).value.pointOfSale;
      await c.reloadTemplates();
      if (!mounted) return;
      _snack('تم إنشاء نقطة البيع — وتم تفعيل كتالوج قوالبها');
      await _load();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TemplatesScreen(posId: pos.id, posName: pos.name),
        ),
      );
      return;
    }

    if (acc == null) {
      // نقطة بيع قديمة بلا حساب مرتبط: نحدّث الاسم فقط.
      final r = await c.posCatalog.updatePointOfSale(
        id: existing.id,
        name: name,
        status: existing.status,
      );
      if (!mounted) return;
      if (r is Failure) _snack((r as Failure).error.message);
      await _load();
      return;
    }

    final updated = await c.posProfile.update(
      posId: existing.id,
      status: existing.status,
      name: name,
      phone: phone,
      existingAccount: acc,
      percentageMode: mode,
      creditLimitMinorUnits: creditMinor,
      clearCreditLimit: creditMinor == null,
    );
    if (!mounted) return;
    if (updated is Failure<PosProfile>) {
      _snack(updated.error.message);
      return;
    }
    await c.reloadTemplates();
    if (!mounted) return;
    _snack('تم حفظ تعديلات نقطة البيع');
    await _load();
  }

  void _posMenu(PointOfSale p) {
    final counts = _templateCounts[p.id] ?? (active: 0, total: 0);
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
                leading: Icon(Icons.tune_rounded, color: context.kayan.primary),
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
                subtitle: Text(
                  '${counts.active} من ${counts.total} قالب نشط',
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TemplatesScreen(posId: p.id, posName: p.name),
                    ),
                  );
                  if (mounted) await _load();
                },
              ),
              ListTile(
                leading: Icon(Icons.done_all_rounded, color: context.netColors.available),
                title: const Text(
                  'تفعيل كل القوالب',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'تستجيب النقطة لكل صيغ الرسائل معاً',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _setAllTemplates(p, true);
                },
              ),
              if (counts.active > 0)
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Color(0xFFF59E0B)),
                  title: const Text(
                    'إيقاف كل القوالب',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setAllTemplates(p, false);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: context.netColors.rejected),
                title: Text(
                  'حذف نقطة البيع',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    color: context.netColors.rejected,
                  ),
                ),
                subtitle: const Text(
                  'أرشفة — تبقى الحركات المالية في السجل',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final r = await AppScope.of(context).posCatalog.updatePointOfSale(
                        id: p.id,
                        name: p.name,
                        status: PointOfSaleStatus.archived,
                      );
                  if (!mounted) return;
                  if (r is Failure) _snack((r as Failure).error.message);
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
              Text(
                'نقاط البيع',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              Text(
                'حسابات النقاط وقوالب رسائلها',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          elevation: 0,
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري تحميل نقاط البيع…')
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم أو رقم الجوال…',
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
                      Expanded(
                        child: RefreshIndicator(
                          color: context.kayan.primary,
                          onRefresh: _load,
                          child: _list(),
                        ),
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: KayanColors.accentPink,
          shape: const StadiumBorder(),
          onPressed: () => _editPos(null),
          icon: const Icon(Icons.add),
          label: const Text(
            'إضافة نقطة بيع',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          AsyncEmptyView(
            message: 'لا توجد نقاط بيع',
            actionLabel: 'إضافة نقطة بيع',
            onAction: () => _editPos(null),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Widget _card(PointOfSale p) {
    final acc = _accounts[p.id];
    final counts = _templateCounts[p.id] ?? (active: 0, total: 0);
    final active = p.status == PointOfSaleStatus.active;
    final busy = _busy.contains(p.id);
    final phone = acc?.notifyPhone ??
        (acc != null && acc.identifiers.isNotEmpty ? acc.identifiers.first : null);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => _posMenu(p),
                ),
                Switch.adaptive(
                  value: active,
                  activeColor: context.kayan.primary,
                  onChanged: busy ? null : (_) => _togglePos(p),
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
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        phone == null ? 'نقطة بيع' : 'نقطة بيع — $phone',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.storefront_outlined, color: context.kayan.primary),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TemplatesScreen(posId: p.id, posName: p.name),
                  ),
                );
                if (mounted) await _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _templateTone(context, counts).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      counts.active == 0
                          ? Icons.notifications_off_rounded
                          : counts.active == counts.total
                              ? Icons.done_all_rounded
                              : Icons.info_outline_rounded,
                      size: 16,
                      color: _templateTone(context, counts),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _templateLabel(counts),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: _templateTone(context, counts),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'إدارة القوالب',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _templateTone(BuildContext context, ({int active, int total}) counts) {
    if (counts.total == 0 || counts.active == 0) return context.netColors.rejected;
    if (counts.active < counts.total) return const Color(0xFFF59E0B);
    return context.netColors.available;
  }

  String _templateLabel(({int active, int total}) counts) {
    if (counts.total == 0) return 'لا قوالب — لن يستجيب النظام لرسائل هذه النقطة';
    if (counts.active == 0) return 'لا قالب نشط من ${counts.total} — الرسائل لن تُعالج';
    if (counts.active < counts.total) {
      return '${counts.active} من ${counts.total} قالب نشط — بعض الصيغ قد لا تُعالج';
    }
    return 'كل القوالب نشطة (${counts.active})';
  }
}
