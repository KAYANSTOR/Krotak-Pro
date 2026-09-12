import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/services/services.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../async_views.dart';

/// Manual direct-sale bottom sheet — visual parity with Kotlin [DirectSaleSheet].
///
/// Fields: phone, amount, name; method: نقدي / آجل; confirm → [SaleService.sellManual].
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

  bool get _phoneValid {
    final p = _phoneCtrl.text.trim();
    return RegExp(r'^7\d{8}$').hasMatch(p);
  }

  int? get _amountMinor {
    final raw = _amountCtrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) return null;
    final major = num.tryParse(raw);
    if (major == null || major <= 0) return null;
    return (major * 100).round();
  }

  String? get _phoneError {
    if (!_submitted) return null;
    final p = _phoneCtrl.text.trim();
    if (p.isEmpty) return 'الرجاء إدخال رقم الجوال';
    if (!_phoneValid) return '9 أرقام تبدأ بـ 7';
    return null;
  }

  String? get _amountError {
    if (!_submitted) return null;
    if (_amountMinor == null) return 'الرجاء إدخال المبلغ';
    return null;
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
    setState(() {
      _status = (r as Failure).error.message;
    });
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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: KayanColors.textSecondary),
                    ),
                    const Spacer(),
                    const Text(
                      'بيع مباشر - يدوي',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: KayanColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0F2F1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 20, color: KayanColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل بيانات العميل لتسجيل بيع يدوي:',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    color: KayanColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _phoneCtrl,
                  hint: 'رقم الجوال',
                  keyboard: TextInputType.phone,
                  errorText: _phoneError,
                  leading: _iconBox(Icons.person_outline),
                  trailing: const Icon(Icons.smartphone, size: 20, color: Color(0xFF9CA3AF)),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                ),
                if (_phoneError == null && !_submitted)
                  const Padding(
                    padding: EdgeInsets.only(right: 12, top: 4),
                    child: Text(
                      '9 أرقام تبدأ بـ 7',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _field(
                  controller: _amountCtrl,
                  hint: 'المبلغ',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  errorText: _amountError,
                  trailing: const Icon(Icons.attach_money, size: 20, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _nameCtrl,
                  hint: 'الاسم',
                  keyboard: TextInputType.name,
                  trailing: const Icon(Icons.person_outline, size: 20, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'طريقة البيع',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: KayanColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _methodChip(
                        label: 'نقدي',
                        icon: Icons.attach_money,
                        selected: _method == ManualSaleMethod.cash,
                        onTap: () => setState(() => _method = ManualSaleMethod.cash),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _methodChip(
                        label: 'آجل',
                        icon: Icons.credit_card,
                        selected: _method == ManualSaleMethod.credit,
                        onTap: () => setState(() => _method = ManualSaleMethod.credit),
                      ),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      color: KayanColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 15,
                            color: KayanColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: KayanColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _busy ? null : _confirm,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, size: 20),
                          label: Text(
                            _busy ? 'جاري التنفيذ…' : 'تأكيد البيع المباشر',
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
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
      ),
    );
  }

  Widget _iconBox(IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: KayanColors.primary),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboard,
    String? errorText,
    Widget? leading,
    Widget? trailing,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      onChanged: (_) {
        if (_submitted) setState(() {});
      },
      style: const TextStyle(fontFamily: 'Tajawal', fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: 'Tajawal',
          color: Color(0xFF9CA3AF),
        ),
        errorText: errorText,
        errorStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
        prefixIcon: leading,
        suffixIcon: trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: errorText != null ? KayanColors.error : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: errorText != null ? KayanColors.error : KayanColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _methodChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFF0FDF4) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? KayanColors.primary : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? KayanColors.primary : KayanColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 16,
                color: selected ? KayanColors.primary : KayanColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
