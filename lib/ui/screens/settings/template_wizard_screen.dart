import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/services/local_message_parser.dart';
import '../../../domain/services/local_transfer_template_activation_service.dart';
import '../../app_scope.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/kayan_palette.dart';

/// معالج إعداد/تعديل قالب التحويل — 4 مراحل مطابق لفيديو Z Net.
class TemplateWizardScreen extends StatefulWidget {
  const TemplateWizardScreen({
    super.key,
    this.existing,
    this.initialWalletId,
    this.initialPosId,
  });

  final TransferTemplate? existing;
  final String? initialWalletId;

  /// Scope a newly-created template to a point-of-sale (parallel to
  /// [initialWalletId]) so it is tagged and filtered like the video shows.
  final String? initialPosId;

  @override
  State<TemplateWizardScreen> createState() => _TemplateWizardScreenState();
}

class _TemplateWizardScreenState extends State<TemplateWizardScreen> {
  static const _steps = ['الرسالة', 'ربط الحقول', 'المعاينة', 'التأكيد'];

  int _step = 0;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  final _sampleCtrl = TextEditingController();
  final _patternCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController(text: '0');
  final _senderNameLabelCtrl = TextEditingController();
  final _noteLabelCtrl = TextEditingController();

  String? _walletId;
  String? _posId;
  TemplateIdentifierKind _kind = TemplateIdentifierKind.phone;
  bool _isActive = true;
  List<Wallet> _wallets = const [];
  List<PointOfSale> _posPoints = const [];

  /// الوضع الذكي (افتراضي لقالب جديد) = نقر على أجزاء الرسالة لربطها بالحقول
  /// وتوليد النمط تلقائياً. الوضع المتقدم = تحرير النمط الخام مباشرة —
  /// يُفتح افتراضياً عند تعديل قالب موجود لأنه قد لا يكون منشأً بالوضع الذكي.
  late bool _advancedMode = widget.existing != null;

  /// الحقل المستهدف حالياً للربط بالنقر (الوضع الذكي فقط).
  String? _activeBindField;

  /// فهرس الكلمة (في الرسالة النموذجية) → الحقل المربوطة به.
  final Map<int, String> _tokenField = {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _senderCtrl.text = e.senderCode ?? '';
      _sampleCtrl.text = e.sampleBody ?? '';
      _patternCtrl.text = e.pattern;
      _priorityCtrl.text = '${e.priority}';
      _walletId = e.walletId;
      _posId = e.posId;
      _kind = e.identifierKind;
      _isActive = e.isActive;
      _senderNameLabelCtrl.text = e.senderNameLabel ?? '';
      _noteLabelCtrl.text = e.noteLabel ?? '';
    } else {
      _walletId = widget.initialWalletId;
      _posId = widget.initialPosId;
      _patternCtrl.text = _defaultPattern(TemplateIdentifierKind.phone);
      _senderNameLabelCtrl.text = 'غير معروف';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWallets());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _senderCtrl.dispose();
    _sampleCtrl.dispose();
    _patternCtrl.dispose();
    _priorityCtrl.dispose();
    _senderNameLabelCtrl.dispose();
    _noteLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWallets() async {
    final r = await AppScope.of(context).wallets.listAll();
    final p = await AppScope.of(context).pointsOfSale.listAll();
    if (!mounted) return;
    setState(() {
      if (r is Success<List<Wallet>>) _wallets = r.value;
      if (p is Success<List<PointOfSale>>) _posPoints = p.value;
    });
  }

  String _defaultPattern(TemplateIdentifierKind kind) {
    return switch (kind) {
      TemplateIdentifierKind.phone =>
        'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
      TemplateIdentifierKind.alternativeNumber =>
        'تم تحويل {amount} الى الرقم البديل {account} مرجع {ref}',
      TemplateIdentifierKind.account =>
        'ايداع {amount} لحساب {account} رقم العملية {ref}',
      TemplateIdentifierKind.senderNameOnly =>
        'تحويل {amount} من المرسل مرجع {ref}',
      TemplateIdentifierKind.balanceRequestCode => '111',
    };
  }

  /// مسميات عربية واضحة: ماذا يمثّل كل نوع معرّف — بلا رموز إنجليزية أو أكواد.
  String _kindLabel(TemplateIdentifierKind k) => switch (k) {
        TemplateIdentifierKind.phone => 'رقم جوال العميل (GSM) — الأكثر استخداماً',
        TemplateIdentifierKind.alternativeNumber => 'الرقم البديل المحفوظ للعميل',
        TemplateIdentifierKind.account => 'رقم أو اسم الحساب البنكي للعميل',
        TemplateIdentifierKind.senderNameOnly => 'اسم المرسل فقط (بدون رقم)',
        TemplateIdentifierKind.balanceRequestCode => 'رمز خاص لطلب الرصيد',
      };

  /// يُضاف المتغير إلى نهاية النمط — بلا كتابة يدوية للأكواد.
  void _insertToken(String token) {
    final current = _patternCtrl.text;
    final needsSpace = current.isNotEmpty && !current.endsWith(' ');
    _patternCtrl.text = '$current${needsSpace ? ' ' : ''}$token';
    _patternCtrl.selection = TextSelection.collapsed(
      offset: _patternCtrl.text.length,
    );
    setState(() {});
  }

  // ===== الوضع الذكي — ربط أجزاء الرسالة النموذجية بالحقول بالنقر =====

  bool _patternHasRef(String pattern) =>
      pattern.contains('{ref}') || pattern.contains('%ref');

  /// مفتاح حقل المعرّف الفعلي حسب نوع المعرّف المختار.
  String get _identifierFieldKey =>
      _kind == TemplateIdentifierKind.phone ? 'phone' : 'account';

  String get _identifierFieldLabel =>
      _kind == TemplateIdentifierKind.phone ? 'رقم الجوال (مطلوب) *' : 'المعرّف (مطلوب) *';

  String _fieldLabel(String key) => switch (key) {
        'amount' => 'المبلغ (مطلوب) *',
        'phone' => 'رقم الجوال (مطلوب) *',
        'account' => 'المعرّف (مطلوب) *',
        'ref' => 'الرقم المرجعي للعملية (اختياري)',
        _ => key,
      };

  IconData _fieldIcon(String key) => switch (key) {
        'amount' => Icons.attach_money_rounded,
        'phone' => Icons.phone_android_rounded,
        'account' => Icons.badge_outlined,
        'ref' => Icons.tag_rounded,
        _ => Icons.text_fields,
      };

  Color _fieldColor(String key, KayanPalette kayan) => switch (key) {
        'amount' => const Color(0xFF0EA5E9),
        'phone' || 'account' => const Color(0xFF16A34A),
        'ref' => const Color(0xFFF59E0B),
        _ => kayan.textTertiary,
      };

  List<String> _sampleWords() {
    final sample = _sampleCtrl.text.trim();
    if (sample.isEmpty) return const [];
    return sample.split(RegExp(r'\s+'));
  }

  /// يبني نمط الاستخراج من كلمات الرسالة النموذجية + ربط كل كلمة بحقلها،
  /// ويكتبه في `_patternCtrl` مباشرة — بقية الشاشة (المعاينة، الحفظ) تقرأ
  /// من `_patternCtrl` دون أي تعديل إضافي.
  void _regeneratePatternFromTokens() {
    final words = _sampleWords();
    if (words.isEmpty) {
      _patternCtrl.text = '';
      return;
    }
    const placeholder = {
      'amount': '{amount}',
      'phone': '{phone}',
      'account': '{account}',
      'ref': '{ref}',
    };
    final parts = <String>[];
    for (var i = 0; i < words.length; i++) {
      final field = _tokenField[i];
      parts.add(field != null ? placeholder[field]! : words[i]);
    }
    _patternCtrl.text = parts.join(' ');
  }

  void _onSampleChangedForSmartMode() {
    // أي تعديل يدوي على الرسالة النموذجية يُبطل الربط السابق — الفهارس لم
    // تعد تعني نفس الكلمات.
    _tokenField.clear();
    _regeneratePatternFromTokens();
  }

  void _toggleTokenBinding(int index) {
    final active = _activeBindField;
    if (active == null) return;
    setState(() {
      if (_tokenField[index] == active) {
        _tokenField.remove(index);
      } else {
        _tokenField[index] = active;
      }
      _regeneratePatternFromTokens();
    });
  }

  void _selectBindField(String key) {
    setState(() => _activeBindField = _activeBindField == key ? null : key);
  }

  bool _validateStep() {
    switch (_step) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) {
          _toast('أدخل اسم القالب');
          return false;
        }
        return true;
      case 1:
        final p = _patternCtrl.text.trim();
        if (p.isEmpty) {
          _toast('أدخل نمط الاستخراج');
          return false;
        }
        if (_kind != TemplateIdentifierKind.balanceRequestCode &&
            !p.contains('{amount}') && !p.contains('%amount')) {
          _toast('النمط يجب أن يحتوي على {amount}');
          return false;
        }
        if (_kind == TemplateIdentifierKind.balanceRequestCode && p.isEmpty) {
          _toast('أدخل رمز طلب الرصيد');
          return false;
        }
        // {ref} (رقم العملية) اختياري — لا نفرضه.
        return true;
      case 3:
        final pr = int.tryParse(_priorityCtrl.text.trim());
        if (pr == null || pr < 0) {
          _toast('الأولوية رقم صحيح ≥ 0');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))),
    );
  }

  void _next() {
    if (!_validateStep()) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _save() async {
    if (!_validateStep()) return;
    setState(() => _saving = true);
    final c = AppScope.of(context);
    final id = widget.existing?.id ?? c.ids.next('tpl');
    final template = TransferTemplate(
      id: id,
      name: _nameCtrl.text.trim(),
      pattern: _patternCtrl.text.trim(),
      isActive: _isActive,
      walletId: _walletId,
      posId: _posId,
      priority: int.tryParse(_priorityCtrl.text.trim()) ?? 0,
      sampleBody: _sampleCtrl.text.trim().isEmpty ? null : _sampleCtrl.text.trim(),
      senderCode: _senderCtrl.text.trim().isEmpty ? null : _senderCtrl.text.trim(),
      identifierKind: _kind,
      senderNameLabel:
          _senderNameLabelCtrl.text.trim().isEmpty ? null : _senderNameLabelCtrl.text.trim(),
      noteLabel: _noteLabelCtrl.text.trim().isEmpty ? null : _noteLabelCtrl.text.trim(),
      // مشتقة تلقائياً: لا معنى لإلزام مرجع لم يُلتقط أصلاً من النمط، وأي
      // نمط يلتقط {ref} صراحة يستفيد من حماية "عدم التكرار" الافتراضية.
      requireReference: _patternHasRef(_patternCtrl.text),
    );
    // حفظ مباشر: القالب الجديد يُضاف إلى جانب القوالب النشطة الأخرى لنفس
    // المصدر — كلها تعمل معاً ويختار [LocalMessageParser] الأنسب بالأولوية.
    final r = await LocalTransferTemplateActivationService(c.transferTemplates)
        .save(template);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r is Failure) {
      _toast(r.error.message);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          backgroundColor: kayan.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 130,
          leading: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: _advancedMode ? context.kayan.primary : kayan.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _advancedMode = !_advancedMode;
                // لا نُعيد توليد النمط تلقائياً عند تبديل الوضع: لو لم يربط
                // المستخدم أي كلمة بعد في الوضع الذكي (مثال شائع: فتح قالب
                // موجود بنمط يدوي جاهز)، إعادة التوليد كانت ستمحو نمطه
                // الحالي بنص حرفي فارغ من الحقول. التوليد يحدث فقط كنتيجة
                // فعلية لربط/إلغاء ربط كلمة (_toggleTokenBinding).
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _advancedMode
                        ? 'الوضع المتقدم: عدّل نمط الاستخراج يدوياً'
                        : 'الوضع الذكي: انقر على كلمات الرسالة لربطها',
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(_advancedMode ? Icons.settings : Icons.settings_outlined, size: 18),
            label: const Text(
              'الوضع المتقدم',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'تعديل القالب' : 'قالب جديد',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: kayan.textPrimary,
                ),
              ),
              Text(
                'إعداد قوالب تحليل رسائل SMS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: kayan.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'رجوع',
              onPressed: () => Navigator.maybePop(context),
              icon: Icon(Icons.arrow_forward, color: cs.onSurface),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _StepIndicator(current: _step, labels: _steps),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: switch (_step) {
                  0 => _stepBasics(kayan),
                  1 => _stepFields(kayan),
                  2 => _stepPreview(kayan),
                  _ => _stepConfirm(kayan),
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _back,
                          child: const Text('السابق', style: TextStyle(fontFamily: 'Tajawal')),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _saving ? null : _next,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _step == 3 ? 'حفظ القالب' : 'التالي',
                                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                              ),
                      ),
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

  Widget _stepBasics(KayanPalette kayan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('المحفظة أو المورد / المرسل'),
        DropdownButtonFormField<String?>(
          value: _walletId != null
              ? 'w:$_walletId'
              : (_posId != null ? 'p:$_posId' : null),
          decoration: _dec(),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('بدون ربط', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            ..._wallets.map(
              (w) => DropdownMenuItem(
                value: 'w:${w.id}',
                child: Text(w.name, style: const TextStyle(fontFamily: 'Tajawal')),
              ),
            ),
            ..._posPoints.map(
              (p) => DropdownMenuItem(
                value: 'p:${p.id}',
                child: Text(p.name, style: const TextStyle(fontFamily: 'Tajawal')),
              ),
            ),
          ],
          onChanged: (v) => setState(() {
            if (v == null) {
              _walletId = null;
              _posId = null;
            } else if (v.startsWith('w:')) {
              _walletId = v.substring(2);
              _posId = null;
            } else if (v.startsWith('p:')) {
              _posId = v.substring(2);
              _walletId = null;
            }
          }),
        ),
        const SizedBox(height: 14),
        _label('نوع معرّف العميل للرسالة'),
        DropdownButtonFormField<TemplateIdentifierKind>(
          value: _kind,
          decoration: _dec(),
          items: TemplateIdentifierKind.values
              .map((k) => DropdownMenuItem(value: k, child: Text(_kindLabel(k), style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13))))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _kind = v;
              if (widget.existing == null) {
                _patternCtrl.text = _defaultPattern(v);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        _label('رمز المصدر / المرسل'),
        TextField(
          controller: _senderCtrl,
          decoration: _dec(hint: 'مثال: JAIB'),
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        const SizedBox(height: 14),
        _label('اسم القالب'),
        TextField(
          controller: _nameCtrl,
          decoration: _dec(hint: 'جيب — تحويل مشترك'),
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        const SizedBox(height: 14),
        _label('نص الرسالة النموذجية'),
        TextField(
          controller: _sampleCtrl,
          maxLines: 4,
          decoration: _dec(hint: 'الصق رسالة حقيقية كمثال…'),
          style: const TextStyle(fontFamily: 'Tajawal', height: 1.4),
          onChanged: (_) {
            if (_advancedMode) {
              // النمط اليدوي في الوضع المتقدم سيد القرار — لا نُعيد توليده،
              // لكن نُبطل أي ربط قديم كي لا يشير لكلمات لم تعد قائمة عند
              // العودة للوضع الذكي لاحقاً.
              _tokenField.clear();
            } else {
              setState(_onSampleChangedForSmartMode);
            }
          },
        ),
      ],
    );
  }

  Widget _stepFields(KayanPalette kayan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_advancedMode) _stepFieldsAdvanced(kayan) else _stepFieldsSmart(kayan),
        const SizedBox(height: 20),
        Divider(color: kayan.border),
        const SizedBox(height: 12),
        _label('اسم المرسل (اختياري)'),
        TextField(
          controller: _senderNameLabelCtrl,
          decoration: _dec(hint: 'غير معروف'),
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        const SizedBox(height: 12),
        _label('البيان / الملاحظة (اختياري)'),
        TextField(
          controller: _noteLabelCtrl,
          decoration: _dec(hint: 'مثال: تحويل مشترك'),
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'هذان الحقلان تسمية ثابتة تُعرض في المعاينة — لا يُستخرجان من نص الرسالة.',
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: kayan.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _stepFieldsAdvanced(KayanPalette kayan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اضغط أي متغير لإضافته إلى النمط بدل كتابته يدوياً:',
          style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip('المبلغ', '{amount}', () => _insertToken('{amount}')),
            _Chip('رقم الجوال', '{phone}', () => _insertToken('{phone}')),
            _Chip('الحساب / الاسم', '{account}', () => _insertToken('{account}')),
            _Chip('المرجع', '{ref}', () => _insertToken('{ref}')),
            if (_posId != null)
              _Chip('عدد الكروت', '{qty}', () => _insertToken('{qty}')),
            if (_posId != null)
              _Chip('رقم التسليم', '{dest}', () => _insertToken('{dest}')),
          ],
        ),
        const SizedBox(height: 16),
        _label('نمط الاستخراج'),
        TextField(
          controller: _patternCtrl,
          maxLines: 5,
          decoration: _dec(
            hint: 'مثال: تم تحويل {amount} ر.ي إلى {phone} رقم العملية {ref}',
          ),
          style: const TextStyle(fontFamily: 'Tajawal', height: 1.4),
        ),
        const SizedBox(height: 12),
        Text(
          'يجب وجود {amount}. المعرّف: {phone} أو {account} حسب نوع المعرّف. {ref} اختياري. لقالب نقطة البيع يمكن استخدام {qty} للعدد و{dest} لرقم التسليم.',
          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textTertiary),
        ),
      ],
    );
  }

  Widget _stepFieldsSmart(KayanPalette kayan) {
    final words = _sampleWords();
    // ترتيب العرض: المبلغ، ثم المعرّف حسب النوع، ثم المرجع.
    final orderedFields = ['amount', _identifierFieldKey, 'ref'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اختر حقلاً من القائمة، ثم انقر على الكلمة المطابقة له داخل الرسالة النموذجية.',
          style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _label('الرسالة النموذجية (تلوين ذكي للقيم المطابقة)'),
        if (words.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kayan.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'أدخل الرسالة النموذجية في الخطوة السابقة أولاً.',
              style: TextStyle(fontFamily: 'Tajawal', color: kayan.textTertiary),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kayan.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kayan.border),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < words.length; i++)
                  _WordChip(
                    text: words[i],
                    field: _tokenField[i],
                    color: _tokenField[i] != null ? _fieldColor(_tokenField[i]!, kayan) : null,
                    enabled: _activeBindField != null,
                    onTap: () => _toggleTokenBinding(i),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        for (final key in orderedFields) _bindFieldRow(kayan, key),
      ],
    );
  }

  Widget _bindFieldRow(KayanPalette kayan, String key) {
    final active = _activeBindField == key;
    final color = _fieldColor(key, kayan);
    final assignedWords = _sampleWords();
    final boundText = _tokenField.entries
        .where((e) => e.value == key)
        .map((e) => assignedWords[e.key])
        .join(' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectBindField(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.08) : kayan.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? color : kayan.border, width: active ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(_fieldIcon(key), size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key == _identifierFieldKey ? _identifierFieldLabel : _fieldLabel(key),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: kayan.textPrimary,
                      ),
                    ),
                    Text(
                      boundText.isEmpty ? 'انقر هنا ثم انقر على الكلمة في الرسالة' : boundText,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: boundText.isEmpty ? kayan.textTertiary : color,
                        fontWeight: boundText.isEmpty ? FontWeight.normal : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (active) Icon(Icons.touch_app_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepPreview(KayanPalette kayan) {
    final sample = _sampleCtrl.text.trim();
    final pattern = _patternCtrl.text.trim();
    String resultText = 'لا توجد رسالة نموذجية للمعاينة.';
    Color resultColor = kayan.textSecondary;
    ParsedTransfer? matched;

    if (sample.isNotEmpty && pattern.isNotEmpty) {
      final parser = LocalMessageParser(templates: [
        TransferTemplate(
          id: 'preview',
          name: _nameCtrl.text.trim().isEmpty ? 'معاينة' : _nameCtrl.text.trim(),
          pattern: pattern,
          isActive: true,
          identifierKind: _kind,
          requireReference: _patternHasRef(pattern),
        ),
      ]);
      final msg = IncomingMessage(
        id: 'preview-msg',
        sender: _senderCtrl.text.trim().isEmpty ? 'PREVIEW' : _senderCtrl.text.trim(),
        body: sample,
        receivedAt: DateTime.now().toUtc(),
        status: MessageProcessingStatus.received,
      );
      final r = parser.parse(msg);
      if (r is Success<ParsedTransfer>) {
        matched = r.value;
        resultText = 'نجح التوليد التلقائي بنجاح!';
        resultColor = context.netColors.available;
      } else {
        resultText = '✗ لم يتطابق النمط مع الرسالة النموذجية\n${(r as Failure).error.message}';
        resultColor = context.netColors.rejected;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('معاينة تحديد النص'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kayan.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kayan.border),
          ),
          child: Text(
            sample.isEmpty ? '—' : sample,
            style: TextStyle(fontFamily: 'Tajawal', height: 1.45, color: kayan.textPrimary),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: resultColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: resultColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    matched != null ? Icons.check_circle : Icons.info_outline,
                    color: resultColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      resultText,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        height: 1.5,
                        color: resultColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (matched != null) ...[
                const SizedBox(height: 10),
                _previewField(
                  kayan,
                  'المبلغ',
                  '${matched.amount.minorUnits / 100}',
                  true,
                ),
                _previewField(
                  kayan,
                  _kind == TemplateIdentifierKind.phone ? 'رقم الجوال' : 'المعرّف',
                  matched.customerIdentifier,
                  true,
                ),
                _previewField(
                  kayan,
                  'اسم المرسل',
                  _senderNameLabelCtrl.text.trim().isEmpty
                      ? 'غير معروف'
                      : _senderNameLabelCtrl.text.trim(),
                  true,
                ),
                _previewField(
                  kayan,
                  'البيان / الملاحظة',
                  _noteLabelCtrl.text.trim().isEmpty ? '—' : _noteLabelCtrl.text.trim(),
                  true,
                ),
                _previewField(
                  kayan,
                  'رقم العملية',
                  matched.reference.isEmpty ? '—' : matched.reference,
                  true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _label('النمط الناتج'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kayan.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(pattern, style: TextStyle(fontFamily: 'Tajawal', color: kayan.textPrimary)),
        ),
      ],
    );
  }

  Widget _previewField(KayanPalette kayan, String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: ok ? context.netColors.available : context.netColors.rejected,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, color: kayan.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kayan.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepConfirm(KayanPalette kayan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تأكيد وحفظ القالب',
          style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 17, color: kayan.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'اضبط أولوية التحليل وحالة القالب، ثم اضغط "حفظ القالب" في الأسفل.',
          style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 18),
        _label('أولوية معالجة القالب'),
        TextField(
          controller: _priorityCtrl,
          keyboardType: TextInputType.number,
          decoration: _dec(hint: '0'),
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        const SizedBox(height: 6),
        Text(
          'توليد تلقائي (يمكنك تعديل القيمة يدوياً)',
          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textTertiary),
        ),
        const SizedBox(height: 16),
        _label('الحالة'),
        DropdownButtonFormField<bool>(
          value: _isActive,
          decoration: _dec(),
          items: const [
            DropdownMenuItem(value: true, child: Text('نشط (مفعل تلقائياً)', style: TextStyle(fontFamily: 'Tajawal'))),
            DropdownMenuItem(value: false, child: Text('متوقف', style: TextStyle(fontFamily: 'Tajawal'))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _isActive = v);
          },
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, fontSize: 13.5)),
      );

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Tajawal'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

/// مؤشر 4 مراحل مطابق لإطارات tpl_60 / tpl_sys130 (دوائر + خطوط + ✓).
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.labels});
  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final teal = context.kayan.primary;
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i <= current
                          ? teal
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                _stepCircle(context, i, teal),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    color: i <= current
                        ? teal
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stepCircle(BuildContext context, int i, Color teal) {
    final done = i < current;
    final active = i == current;
    final showPerson = active && i == 0;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done || active ? teal : Theme.of(context).colorScheme.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(
          color: done || active ? teal : Theme.of(context).colorScheme.outlineVariant,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: teal.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : showPerson
              ? const Icon(Icons.person, size: 18, color: Colors.white)
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: active ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
    );
  }
}

/// شريحة متغير: المسمّى العربي أولاً ثم الرمز، والضغط يضيفه للنمط.
class _Chip extends StatelessWidget {
  const _Chip(this.label, this.token, this.onTap);

  final String label;
  final String token;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.kayan.primary;
    return Material(
      color: primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 14, color: primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  color: primary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                token,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w500,
                  color: primary.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// كلمة قابلة للنقر من الرسالة النموذجية في الوضع الذكي — تتلوّن بلون
/// الحقل المربوطة به، أو رمادية محايدة عند عدم الربط.
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.text,
    required this.field,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final String? field;
  final Color? color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    final bound = field != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bound ? color!.withValues(alpha: 0.15) : kayan.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: bound ? color! : Colors.transparent),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: bound ? FontWeight.w800 : FontWeight.w500,
            color: bound ? color : kayan.textPrimary,
          ),
        ),
      ),
    );
  }
}
