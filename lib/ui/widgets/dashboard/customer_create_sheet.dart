import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/phone_normalizer.dart';
import '../../app_scope.dart';
import '../../platform/contact_picker_bridge.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../net/net_sheet.dart';

/// حقول إنشاء حساب مشترك جديد — مطابقة لتصميم «إنشاء حساب مشترك جديد».
///
/// كل الحقول اختيارية عدا واحد على الأقل من: جوال، استلام الرسائل، رقم بديل.
/// نفس استدعاءات `CustomerService.create` + `addIdentifier` الحالية تمامًا.
class _CustField {
  const _CustField({
    required this.key,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.hint,
    this.maxLength,
    this.digitsOnly = false,
  });

  final String key;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final String? hint;
  final int? maxLength;
  final bool digitsOnly;
}

const _custFields = <_CustField>[
  _CustField(
    key: 'gsm',
    label: 'رقم الجوال (GSM)',
    icon: Icons.phone_android_rounded,
    keyboardType: TextInputType.phone,
    maxLength: 9,
    digitsOnly: true,
  ),
  _CustField(
    key: 'walletPhone',
    label: 'رقم جوال بديل لاستلام الرسائل',
    icon: Icons.sms_rounded,
    keyboardType: TextInputType.phone,
    maxLength: 9,
    digitsOnly: true,
  ),
  _CustField(
    key: 'name',
    label: 'اسم المشترك',
    icon: Icons.person_rounded,
  ),
  _CustField(
    key: 'onecash',
    label: 'اسم المرسل فقط (ONE CASH)',
    icon: Icons.alternate_email_rounded,
  ),
  _CustField(
    key: 'floosak',
    label: 'اسم المرسل فقط (FLOOSAK)',
    icon: Icons.alternate_email_rounded,
  ),
  _CustField(
    key: 'jaibPhone',
    label: 'الرقم البديل (JAIB)',
    icon: Icons.phone_android_rounded,
    keyboardType: TextInputType.phone,
    maxLength: 12,
    digitsOnly: true,
  ),
  _CustField(
    key: 'jaibName',
    label: 'اسم المرسل فقط (JAIB)',
    icon: Icons.alternate_email_rounded,
  ),
];

/// الورقة تعيد رقم الحساب المُنشأ أو null عند الإلغاء/الفشل.
class CustomerCreateSheet extends StatefulWidget {
  const CustomerCreateSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return NetSheet.show<String>(
      context,
      builder: (_) => const CustomerCreateSheet(),
    );
  }

  @override
  State<CustomerCreateSheet> createState() => _CustomerCreateSheetState();
}

class _CustomerCreateSheetState extends State<CustomerCreateSheet> {
  final _controllers = {for (final f in _custFields) f.key: TextEditingController()};
  final _contactPicker = ContactPickerBridge();
  bool _busy = false;
  bool _picking = false;
  String? _status;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _controllers[key]!.text.trim();

  String? get _gsm => _text('gsm').isEmpty ? null : _text('gsm');
  String? get _walletPhone =>
      _text('walletPhone').isEmpty ? null : _text('walletPhone');
  String? get _name => _text('name').isEmpty ? null : _text('name');
  String? get _onecash => _text('onecash').isEmpty ? null : _text('onecash');
  String? get _floosak => _text('floosak').isEmpty ? null : _text('floosak');
  String? get _jaibPhone => _text('jaibPhone').isEmpty ? null : _text('jaibPhone');
  String? get _jaibName => _text('jaibName').isEmpty ? null : _text('jaibName');

  bool get _hasAnyIdentity =>
      _gsm != null ||
      _walletPhone != null ||
      _onecash != null ||
      _floosak != null ||
      _jaibPhone != null ||
      _jaibName != null;

  /// جوال الهوية الأساسي: الجوال أولاً، ثم رقم الاستلام، ثم بديل JAIB.
  String? get _primaryPhone => _gsm ?? _walletPhone ?? _jaibPhone;

  /// الحساب المالي منقول على الهوية الأساسية إن وُجد؛ وإلا على اسم مرسل واحد.
  String? get _primaryExternal => _onecash ?? _floosak ?? _jaibName;

  bool get _valid => _hasAnyIdentity && _status == null;

  Future<void> _pickContact(_CustField field) async {
    if (_picking || field.digitsOnly == false) return;
    setState(() => _picking = true);
    final phone = await _contactPicker.pickPhone();
    if (!mounted) return;
    setState(() => _picking = false);
    if (phone == null || phone.isEmpty) return;
    final ctrl = _controllers[field.key]!;
    ctrl.text = phone;
    ctrl.selection = TextSelection.collapsed(offset: phone.length);
  }

  Future<void> _submit() async {
    if (!_hasAnyIdentity) {
      setState(() => _status = 'أدخل رقم جوال أو اسم مرسل واحد على الأقل');
      return;
    }
    final gsm = _gsm;
    if (gsm != null && !RegExp(r'^7\d{8}$').hasMatch(PhoneNormalizer.digitsOnly(gsm))) {
      setState(() => _status = 'رقم الجوال يجب أن يكون 9 أرقام تبدأ بـ 7');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });

    final c = AppScope.of(context);
    final displayName = _name ?? _primaryPhone ?? _primaryExternal ?? 'مشترك';
    final primaryType = _primaryPhone != null
        ? CustomerIdentifierType.phoneNumber
        : CustomerIdentifierType.externalReference;
    final primaryValue = _primaryPhone ?? _primaryExternal ?? '';

    final created = await c.customerService.create(
      displayName: displayName,
      identifierType: primaryType,
      identifierValue: primaryValue,
    );
    if (!mounted) return;
    if (created is Failure<Customer>) {
      setState(() {
        _busy = false;
        _status = (created as Failure).error.message;
      });
      return;
    }
    final customer = (created as Success<Customer>).value;

    // إضافة بقية المعرفات المعبأة (الأساسية محفوظة داخل create).
    Future<Result<void>>? lastAdd;
    void queueAdd(CustomerIdentifierType type, String value, {bool isPrimary = false}) {
      lastAdd = c.customerService.addIdentifier(
        customerId: customer.id,
        type: type,
        value: value,
        isPrimary: isPrimary,
      );
    }

    if (gsm != null && primaryValue != gsm) {
      queueAdd(CustomerIdentifierType.phoneNumber, gsm);
    }
    if (_walletPhone != null && primaryValue != _walletPhone) {
      queueAdd(CustomerIdentifierType.phoneNumber, _walletPhone!);
    }
    if (_onecash != null && primaryValue != _onecash) {
      queueAdd(CustomerIdentifierType.externalReference, _onecash!);
    }
    if (_floosak != null && primaryValue != _floosak) {
      queueAdd(CustomerIdentifierType.externalReference, _floosak!);
    }
    if (_jaibPhone != null && primaryValue != _jaibPhone) {
      queueAdd(CustomerIdentifierType.phoneNumber, _jaibPhone!);
    }
    if (_jaibName != null && primaryValue != _jaibName) {
      queueAdd(CustomerIdentifierType.externalReference, _jaibName!);
    }

    if (lastAdd != null) {
      final r = await lastAdd!;
      if (!mounted) return;
      if (r is Failure) {
        setState(() {
          _busy = false;
          _status =
              'الحساب أُنشئ لكن فشل حفظ أحد المعرفات: ${(r as Failure).error.message}';
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(customer.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return NetSheet(
      title: 'إنشاء حساب مشترك جديد',
      subtitle: 'أدخل بيانات المشترك لإنشاء حساب جديد له في دفتر الحسابات:',
      icon: Icons.person_add_alt_rounded,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.xl,
          NetSpacing.lg,
          NetSpacing.xl,
          NetSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _custFields.length; i++) ...[
              _fieldBox(_custFields[i]),
              if (i < _custFields.length - 1) const SizedBox(height: NetSpacing.md),
            ],
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
          ],
        ),
      ),
      footer: Row(
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(
              'إلغاء',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy ? null : _submit,
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
              label: const Text('تأكيد الإنشاء'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldBox(_CustField field) {
    final palette = KayanPalette.of(context);
    final ctrl = _controllers[field.key]!;
    final filled = ctrl.text.trim().isNotEmpty;
    final isPhone = field.digitsOnly;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: NetRadii.mdAll,
        border: Border.all(
          color: filled ? palette.primary : palette.border,
          width: filled ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.md,
        vertical: NetSpacing.xxs,
      ),
      child: Row(
        children: [
          Icon(
            field.icon,
            size: NetSizes.iconMd,
            color: palette.primary,
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: field.keyboardType,
              maxLength: field.maxLength,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                if (field.digitsOnly) FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: field.label,
                hintStyle: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
                border: InputBorder.none,
                counterText: '',
                isDense: true,
              ),
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (isPhone)
            InkWell(
              borderRadius: NetRadii.smAll,
              onTap: _picking ? null : () => _pickContact(field),
              child: Padding(
                padding: const EdgeInsets.all(NetSpacing.xs),
                child: _picking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
    );
  }
}
