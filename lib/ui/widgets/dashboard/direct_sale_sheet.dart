import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/phone_normalizer.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/money.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/services/services.dart';
import '../../app_scope.dart';
import '../../../platform/contact_picker_bridge.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';

/// بيع يدوي: نقدي / آجل / هدية / نقطة بيع — 1.0.9.
///
/// طبقة العرض فقط: نفس `sellManual` ونفس الـoperationId — بلا أي تغيير منطقي.
/// الإضافات الواجهية: اختيار الرقم من جهات اتصال الجهاز وكشف عميل موجود مسبقًا.
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
  final _contactPicker = ContactPickerBridge();
  ManualSaleMethod _method = ManualSaleMethod.cash;
  bool _submitted = false;
  bool _busy = false;
  bool _pickingContact = false;
  String? _status;
  String? _operationId;

  /// نتيجة فحص النظام للرقم المُدخل: عميل موجود / غير معروف / لا شيء.
  String? _existingCustomerName;

  /// اقتراحات أرقام العملاء أثناء الكتابة (من قاعدة البيانات الحقيقية فقط).
  List<CustomerPhoneSuggestion> _phoneSuggestions = const [];
  bool _suggesting = false;
  int _suggestSeq = 0;
  Timer? _suggestDebounce;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _phoneCtrl.removeListener(_onPhoneChanged);
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

  void _onPhoneChanged() {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _suggestDebounce?.cancel();
      if (_phoneSuggestions.isNotEmpty || _existingCustomerName != null || _suggesting) {
        setState(() {
          _phoneSuggestions = const [];
          _existingCustomerName = null;
          _suggesting = false;
        });
      }
      return;
    }
    // Debounce 250ms — لا استعلام مكلف لكل حرف.
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runPhoneSuggestions());
    });
  }

  Future<void> _runPhoneSuggestions() async {
    final phone = _phoneCtrl.text.trim();
    final seq = ++_suggestSeq;
    if (phone.isEmpty) return;

    if (mounted) setState(() => _suggesting = true);
    final c = AppScope.of(context);
    final suggestResult =
        await c.customers.suggestPhonesByPrefix(phone, limit: 8);
    if (!mounted || seq != _suggestSeq) return;

    List<CustomerPhoneSuggestion> suggestions = const [];
    if (suggestResult is Success<List<CustomerPhoneSuggestion>>) {
      suggestions = suggestResult.value;
    }

    String? existingName;
    if (_phoneValid) {
      final r = await c.customers.findByIdentifier(phone);
      if (!mounted || seq != _suggestSeq) return;
      if (r is Success<Customer?> && r.value != null) {
        final customer = r.value!;
        if (customer.status == CustomerStatus.active ||
            customer.status == CustomerStatus.provisional) {
          existingName = customer.displayName;
          if (_nameCtrl.text.trim().isEmpty &&
              customer.displayName.trim().isNotEmpty) {
            _nameCtrl.text = customer.displayName;
          }
        }
      }
    }

    setState(() {
      _phoneSuggestions = suggestions;
      _existingCustomerName = existingName;
      _suggesting = false;
    });
  }

  void _applySuggestion(CustomerPhoneSuggestion s) {
    _phoneCtrl.removeListener(_onPhoneChanged);
    _phoneCtrl.text = s.phone;
    _phoneCtrl.selection = TextSelection.collapsed(offset: s.phone.length);
    if (s.displayName.trim().isNotEmpty) {
      _nameCtrl.text = s.displayName;
    }
    _phoneCtrl.addListener(_onPhoneChanged);
    setState(() {
      _phoneSuggestions = const [];
      _existingCustomerName = s.displayName;
      _suggesting = false;
    });
  }

  Future<void> _pickContact() async {
    if (_pickingContact) return;
    setState(() => _pickingContact = true);
    final phone = await _contactPicker.pickPhone();
    if (!mounted) return;
    setState(() => _pickingContact = false);
    if (phone == null || phone.isEmpty) return;
    _phoneCtrl.text = phone;
    _phoneCtrl.selection = TextSelection.collapsed(offset: phone.length);
    await _runPhoneSuggestions();
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
    final inset = MediaQuery.viewInsetsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final net = context.netColors;
    final exists = _existingCustomerName != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset.bottom),
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
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: NetSizes.badge,
                      height: NetSizes.badge,
                      decoration: BoxDecoration(
                        color: palette.iconBadgeBackground,
                        borderRadius: NetRadii.mdAll,
                      ),
                      child: Icon(
                        Icons.point_of_sale_rounded,
                        color: palette.primary,
                        size: NetSizes.iconMd,
                      ),
                    ),
                    const SizedBox(width: NetSpacing.md),
                    Text(
                      'بيع مباشر - يدوي',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: NetSpacing.md),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: NetSpacing.lg),
                Text(
                  'أدخل بيانات العميل لتسجيل بيع يدوي:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),

                // ── رقم الجوال + منتقي جهات الاتصال ──
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'رقم الجوال',
                    errorText: _submitted && !_phoneValid
                        ? '9 أرقام تبدأ بـ 7'
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: NetRadii.mdAll,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_android_rounded,
                        size: NetSizes.iconMd,
                        color: _phoneValid ? net.success : palette.primary,
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            const _WesternDigitsFormatter(),
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          decoration: const InputDecoration.collapsed(
                            hintText: '7XXXXXXXX',
                          ),
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (_phoneValid) ...[
                        Icon(
                          Icons.verified_rounded,
                          size: NetSizes.iconMd,
                          color: net.success,
                        ),
                        const SizedBox(width: NetSpacing.sm),
                      ],
                      InkWell(
                        borderRadius: NetRadii.smAll,
                        onTap: _pickingContact ? null : _pickContact,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.iconBadgeBackground,
                            borderRadius: NetRadii.smAll,
                          ),
                          child: _pickingContact
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.contacts_rounded,
                                  size: NetSizes.iconMd,
                                  color: palette.primary,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NetSpacing.xs),

                // ── اقتراحات أرقام العملاء (أثناء الكتابة) ──
                if (_phoneSuggestions.isNotEmpty) ...[
                  const SizedBox(height: NetSpacing.sm),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: NetRadii.mdAll,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: NetSpacing.xs),
                      itemCount: _phoneSuggestions.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final s = _phoneSuggestions[index];
                        return InkWell(
                          onTap: () => _applySuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NetSpacing.md,
                              vertical: NetSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_search_rounded,
                                  size: 18,
                                  color: palette.primary,
                                ),
                                const SizedBox(width: NetSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.phone,
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      if (s.displayName.trim().isNotEmpty)
                                        Text(
                                          s.displayName,
                                          style: TextStyle(
                                            fontFamily: NetTypography.family,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: palette.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (s.status == CustomerStatus.provisional)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.iconBadgeBackground,
                                      borderRadius: NetRadii.pillAll,
                                    ),
                                    child: Text(
                                      'مؤقت',
                                      style: TextStyle(
                                        fontFamily: NetTypography.family,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: palette.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else if (_suggesting && _phoneCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: NetSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'جاري البحث عن أرقام…',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
                ],

                // ── كشف عميل موجود (عرض فقط) ──
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(top: NetSpacing.xs),
                    child: exists
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NetSpacing.md,
                              vertical: NetSpacing.xs + 2,
                            ),
                            decoration: BoxDecoration(
                              color: net.successContainer,
                              borderRadius: NetRadii.pillAll,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_user_rounded,
                                  size: 15,
                                  color: net.success,
                                ),
                                const SizedBox(width: NetSpacing.xs),
                                Text(
                                  'عميل موجود · $_existingCustomerName',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: net.success,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _phoneValid
                            ? Text(
                                'عميل غير معروف — يُنشأ تلقائيًا عند البيع',
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textSecondary,
                                ),
                              )
                            : Text(
                                'اختر الرقم من جهات الاتصال أو أدخله يدويًا',
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 12,
                                  color: palette.textTertiary,
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: NetSpacing.md),

                // ── المبلغ ──
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    errorText: _submitted && _amountMinor == null
                        ? 'أدخل مبلغًا صالحًا'
                        : null,
                    prefixIcon: Icon(
                      Icons.payments_rounded,
                      size: NetSizes.iconMd,
                      color: palette.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: NetRadii.mdAll,
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (_method == ManualSaleMethod.gift) ...[
                  const SizedBox(height: NetSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.redeem_rounded,
                        size: 14,
                        color: context.netColors.premium,
                      ),
                      const SizedBox(width: NetSpacing.xs),
                      Expanded(
                        child: Text(
                          'فئة كرت الهدية تُحدد تلقائيًا بمطابقة المبلغ مع الفئات النشطة',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 11.5,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: NetSpacing.md),

                // ── الاسم ──
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'الاسم',
                    prefixIcon: Icon(
                      Icons.person_rounded,
                      size: NetSizes.iconMd,
                      color: palette.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: NetRadii.mdAll,
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),

                // ── طريقة البيع ──
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
                Row(
                  children: [
                    for (var i = 0; i < ManualSaleMethod.values.length; i++) ...[
                      if (i > 0) const SizedBox(width: NetSpacing.sm),
                      Expanded(child: _methodChip(ManualSaleMethod.values[i])),
                    ],
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
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
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
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _busy ? 'جاري التنفيذ…' : 'تأكيد البيع المباشر',
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

  Widget _methodChip(ManualSaleMethod m) {
    final palette = context.palette;
    final selected = _method == m;
    final labels = {
      ManualSaleMethod.cash: 'نقدي',
      ManualSaleMethod.credit: 'آجل',
      ManualSaleMethod.gift: 'هدية',
      ManualSaleMethod.pos: 'نقطة بيع',
    };
    final icons = {
      ManualSaleMethod.cash: Icons.payments_rounded,
      ManualSaleMethod.credit: Icons.receipt_long_rounded,
      ManualSaleMethod.gift: Icons.redeem_rounded,
      ManualSaleMethod.pos: Icons.storefront_rounded,
    };
    return InkWell(
      borderRadius: NetRadii.mdAll,
      onTap: () => setState(() => _method = m),
      child: AnimatedContainer(
        duration: NetDurations.fast,
        padding: const EdgeInsets.symmetric(vertical: NetSpacing.md),
        decoration: BoxDecoration(
          color: selected ? palette.primary : palette.surfaceVariant,
          borderRadius: NetRadii.mdAll,
          border: Border.all(
            color: selected ? palette.primary : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icons[m],
              size: 20,
              color: selected ? palette.onPrimary : palette.textSecondary,
            ),
            const SizedBox(height: NetSpacing.xs),
            Text(
              labels[m]!,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? palette.onPrimary : palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// يحوّل الأرقام العربية/الفارسية إلى لاتينية أثناء الكتابة في حقل الجوال.
final class _WesternDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final western = PhoneNormalizer.toWesternDigits(newValue.text);
    if (western == newValue.text) return newValue;
    return TextEditingValue(
      text: western,
      selection: TextSelection.collapsed(offset: western.length),
    );
  }
}
