import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/services/services.dart';
import '../../app_scope.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: NetRadii.sheetTop,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              NetSpacing.xxl,
              NetSpacing.sm,
              NetSpacing.xxl,
              NetSpacing.lg + bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: NetSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: NetRadii.pillAll,
                    ),
                  ),
                ),
                Text(
                  'بيع مباشر - يدوي',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: InputDecoration(
                    labelText: 'رقم الجوال',
                    errorText: _submitted && !_phoneValid
                        ? '9 أرقام تبدأ بـ 7'
                        : null,
                  ),
                ),
                const SizedBox(height: NetSpacing.md),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    errorText: _submitted && _amountMinor == null
                        ? 'أدخل مبلغًا صالحًا'
                        : null,
                  ),
                ),
                const SizedBox(height: NetSpacing.md),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: NetSpacing.lg),
                Text(
                  'طريقة البيع',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: NetSpacing.sm),
                Wrap(
                  spacing: NetSpacing.sm,
                  runSpacing: NetSpacing.sm,
                  children: [
                    for (final m in ManualSaleMethod.values)
                      ChoiceChip(
                        label: Text(
                          _label(m),
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 12.5,
                            fontWeight: _method == m
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _method == m ? Colors.white : scheme.onSurface,
                          ),
                        ),
                        selected: _method == m,
                        showCheckmark: false,
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surface,
                        side: BorderSide(
                          color: _method == m
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: NetRadii.pillAll,
                        ),
                        onSelected: (_) => setState(() => _method = m),
                      ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: NetSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: NetSizes.iconSm,
                        color: context.netColors.rejected,
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Text(
                          _status!,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.netColors.rejected,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: NetSpacing.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _confirm,
                  child: Text(_busy ? 'جاري التنفيذ…' : 'تأكيد البيع المباشر'),
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
