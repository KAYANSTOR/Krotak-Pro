import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/services/local_message_parser.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';

/// معالج إعداد/تعديل قالب التحويل — 4 مراحل مطابق لفيديو Z Net.
class TemplateWizardScreen extends StatefulWidget {
  const TemplateWizardScreen({
    super.key,
    this.existing,
    this.initialWalletId,
  });

  final TransferTemplate? existing;
  final String? initialWalletId;

  @override
  State<TemplateWizardScreen> createState() => _TemplateWizardScreenState();
}

class _TemplateWizardScreenState extends State<TemplateWizardScreen> {
  static const _steps = ['الأساسيات', 'ربط الحقول', 'المعاينة', 'التأكيد'];

  int _step = 0;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  final _sampleCtrl = TextEditingController();
  final _patternCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController(text: '0');

  String? _walletId;
  TemplateIdentifierKind _kind = TemplateIdentifierKind.phone;
  bool _isActive = true;
  List<Wallet> _wallets = const [];

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
      _kind = e.identifierKind;
      _isActive = e.isActive;
    } else {
      _walletId = widget.initialWalletId;
      _patternCtrl.text = _defaultPattern(TemplateIdentifierKind.phone);
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
    super.dispose();
  }

  Future<void> _loadWallets() async {
    final r = await AppScope.of(context).wallets.listAll();
    if (!mounted) return;
    if (r is Success<List<Wallet>>) {
      setState(() => _wallets = r.value);
    }
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
      TemplateIdentifierKind.balanceRequestCode =>
        'رصيد {amount} كود {account} مرجع {ref}',
    };
  }

  String _kindLabel(TemplateIdentifierKind k) => switch (k) {
        TemplateIdentifierKind.phone => 'الجوال (GSM)',
        TemplateIdentifierKind.alternativeNumber => 'الرقم البديل (Alternative Number)',
        TemplateIdentifierKind.account => 'رقم الحساب',
        TemplateIdentifierKind.senderNameOnly => 'اسم المرسل فقط (Sender Name Only)',
        TemplateIdentifierKind.balanceRequestCode => 'كود خاص (Balance Request Code)',
      };

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
        if (!p.contains('{amount}') && !p.contains('%amount')) {
          _toast('النمط يجب أن يحتوي على {amount}');
          return false;
        }
        if (!p.contains('{ref}') && !p.contains('%ref')) {
          _toast('النمط يجب أن يحتوي على {ref}');
          return false;
        }
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
      priority: int.tryParse(_priorityCtrl.text.trim()) ?? 0,
      sampleBody: _sampleCtrl.text.trim().isEmpty ? null : _sampleCtrl.text.trim(),
      senderCode: _senderCtrl.text.trim().isEmpty ? null : _senderCtrl.text.trim(),
      identifierKind: _kind,
    );
    final r = await c.transferTemplates.save(template);
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
              foregroundColor: const Color(0xFF0F766E),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'أنت في الوضع المتقدم لإعداد القوالب',
                    style: TextStyle(fontFamily: 'Tajawal'),
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.settings, size: 18),
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
                          backgroundColor: const Color(0xFF0F766E),
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
        _label('المحفظة (اختياري)'),
        DropdownButtonFormField<String?>(
          value: _walletId,
          decoration: _dec(),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('بدون ربط بمحفظة', style: TextStyle(fontFamily: 'Tajawal'))),
            ..._wallets.map(
              (w) => DropdownMenuItem(value: w.id, child: Text(w.name, style: const TextStyle(fontFamily: 'Tajawal'))),
            ),
          ],
          onChanged: (v) => setState(() => _walletId = v),
        ),
        const SizedBox(height: 14),
        _label('نوع معرّف المشترك للرسالة'),
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
        ),
      ],
    );
  }

  Widget _stepFields(KayanPalette kayan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اربط حقول الاستخراج داخل النمط. استخدم العناصر النائبة:',
          style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _Chip('{amount}'),
            _Chip('{phone}'),
            _Chip('{account}'),
            _Chip('{ref}'),
          ],
        ),
        const SizedBox(height: 16),
        _label('نمط الاستخراج'),
        TextField(
          controller: _patternCtrl,
          maxLines: 5,
          decoration: _dec(hint: '… {amount} … {phone} … {ref}'),
          style: const TextStyle(fontFamily: 'Tajawal', height: 1.4),
        ),
        const SizedBox(height: 12),
        Text(
          'يجب وجود {amount} و {ref}. المعرّف: {phone} أو {account} حسب نوع المعرّف.',
          style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textTertiary),
        ),
      ],
    );
  }

  Widget _stepPreview(KayanPalette kayan) {
    final sample = _sampleCtrl.text.trim();
    final pattern = _patternCtrl.text.trim();
    String resultText = 'لا توجد رسالة نموذجية للمعاينة.';
    Color resultColor = kayan.textSecondary;

    if (sample.isNotEmpty && pattern.isNotEmpty) {
      final parser = LocalMessageParser(templates: [
        TransferTemplate(
          id: 'preview',
          name: _nameCtrl.text.trim().isEmpty ? 'معاينة' : _nameCtrl.text.trim(),
          pattern: pattern,
          isActive: true,
          identifierKind: _kind,
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
        final t = r.value;
        resultText =
            '✓ تطابق ناجح\nالمبلغ: ${t.amount.minorUnits / 100} ${t.amount.currencyCode}\nالمعرّف: ${t.customerIdentifier} (${t.identifierType.name})\nالمرجع: ${t.reference}';
        resultColor = const Color(0xFF059669);
      } else {
        resultText = '✗ لم يتطابق النمط مع الرسالة النموذجية\n${(r as Failure).error.message}';
        resultColor = const Color(0xFFDC2626);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('الرسالة النموذجية'),
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
        const SizedBox(height: 14),
        _label('النمط'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kayan.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(pattern, style: TextStyle(fontFamily: 'Tajawal', color: kayan.textPrimary)),
        ),
        const SizedBox(height: 16),
        _label('نتيجة المعاينة'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: resultColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: resultColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            resultText,
            style: TextStyle(fontFamily: 'Tajawal', height: 1.5, color: resultColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
    const teal = Color(0xFF0F766E);
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
                      color: i <= current ? teal : const Color(0xFFCBD5E1),
                    ),
                  ),
                _stepCircle(i, teal),
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
                    color: i <= current ? teal : const Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stepCircle(int i, Color teal) {
    final done = i < current;
    final active = i == current;
    final showPerson = active && i == 0;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done || active ? teal : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: done || active ? teal : const Color(0xFFCBD5E1),
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
                    color: active ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
    );
  }
}
