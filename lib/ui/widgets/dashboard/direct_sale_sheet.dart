import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/services/services.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';

/// بيع يدوي: نقدي / آجل / هدية / نقطة بيع — 1.0.9.
class DirectSaleSheet extends StatefulWidget {
  const DirectSaleSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DirectSaleSheet(),
    );
  }

  @override
  State<DirectSaleSheet> createState() => _DirectSaleSheetState();
}

class _DirectSaleSheetState extends State<DirectSaleSheet> {
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  ManualSaleMethod _method = ManualSaleMethod.cash;
  bool _submitted = false;
  bool _busy = false;
  String? _status;
  String? _operationId;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _phoneValid => RegExp(r'^7\d{8}$').hasMatch(_phoneCtrl.text.trim());

  int? get _amountMinor {
    final raw = _amountCtrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) return null;
    final major = num.tryParse(raw);
    if (major == null || major <= 0) return null;
    return (major * 100).round();
  }

  Future<void> _confirm() async {
    setState(() {
      _submitted = true;
      _status = null;
    });
    if (!_phoneValid || _amountMinor == null) return;
    setState(() => _busy = true);
    final c = AppScope.of(context);
    _operationId ??= c.ids.next('manual-sale');
    final r = await c.saleService.sellManual(
      phone: _phoneCtrl.text.trim(),
      displayName: _nameCtrl.text.trim(),
      amount: Money(minorUnits: _amountMinor!, currencyCode: 'YER'),
      method: _method,
      operationId: _operationId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Success<Sale>) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _status = (r as Failure).error.message);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(50)),
                  ),
                ),
                const Text(
                  'بيع مباشر - يدوي',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  decoration: InputDecoration(
                    labelText: 'رقم الجوال',
                    errorText: _submitted && !_phoneValid ? '9 أرقام تبدأ بـ 7' : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    errorText: _submitted && _amountMinor == null ? 'أدخل مبلغًا صالحًا' : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'الاسم',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                const SizedBox(height: 16),
                const Text('طريقة البيع', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in ManualSaleMethod.values)
                      ChoiceChip(
                        label: Text(_label(m), style: const TextStyle(fontFamily: 'Tajawal')),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                        selectedColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                      ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: const TextStyle(fontFamily: 'Tajawal', color: KayanColors.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KayanColors.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _confirm,
                  child: Text(
                    _busy ? 'جاري التنفيذ…' : 'تأكيد البيع المباشر',
                    style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(ManualSaleMethod m) => switch (m) {
        ManualSaleMethod.cash => 'نقدي',
        ManualSaleMethod.credit => 'آجل',
        ManualSaleMethod.gift => 'هدية',
        ManualSaleMethod.pos => 'نقطة بيع',
      };
}
