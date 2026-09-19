import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../labels/net_labels.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../async_views.dart';
import 'net_sheet.dart';

/// تفاصيل العملية — مطابقة تخطيط إطار «بيانات الحركة» في التطبيق المرجعي
/// (رأس، مبلغ مميّز، صفوف تفاصيل، إجراءا مشاركة/حفظ) مع مسميات NET وألوانها.
///
/// قراءة فقط: لا تعدّل أي حركة أو رصيد، وتقرأ العميل المرتبط لعرض المستفيد.
class NetTransactionDetailSheet extends StatefulWidget {
  const NetTransactionDetailSheet({super.key, required this.transaction});

  final Transaction transaction;

  static Future<void> show(
    BuildContext context,
    Transaction transaction,
  ) async {
    await NetSheet.show<void>(
      context,
      builder: (_) => NetTransactionDetailSheet(transaction: transaction),
    );
  }

  @override
  State<NetTransactionDetailSheet> createState() =>
      _NetTransactionDetailSheetState();
}

class _NetTransactionDetailSheetState extends State<NetTransactionDetailSheet> {
  String? _customerName;
  String? _customerPhone;
  bool _loadingCustomer = false;

  Transaction get _tx => widget.transaction;

  bool get _isInflow =>
      _tx.type == TransactionType.deposit ||
      _tx.type == TransactionType.reward ||
      _tx.type == TransactionType.reversal;

  @override
  void initState() {
    super.initState();
    final id = _tx.customerId;
    if (id != null && id.isNotEmpty) {
      _loadingCustomer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomer(id));
    }
  }

  Future<void> _loadCustomer(String customerId) async {
    final c = AppScope.of(context);
    final found = await c.customers.findById(customerId);
    final name = found is Success<Customer?> ? found.value?.displayName : null;

    String? phone;
    final ids = await c.customers.listIdentifiers(customerId);
    if (ids is Success<List<CustomerIdentifier>>) {
      final phones = ids.value
          .where((i) => i.type == CustomerIdentifierType.phoneNumber)
          .toList();
      if (phones.isNotEmpty) {
        phone = phones.firstWhere((i) => i.isPrimary, orElse: () => phones.first).value;
      }
    }

    if (!mounted) return;
    setState(() {
      _loadingCustomer = false;
      _customerName = name;
      _customerPhone = phone;
    });
  }

  String get _amountText => formatAmountOnly(_tx.amount.minorUnits / 100.0);

  String get _currencyLabel =>
      _tx.amount.currencyCode == 'YER' ? 'ر.ي' : _tx.amount.currencyCode;

  String get _reference =>
      (_tx.reference ?? '').trim().isEmpty ? _tx.id : _tx.reference!.trim();

  static String _two(int value) => value.toString().padLeft(2, '0');

  String get _dateLabel {
    final local = _tx.createdAt.toLocal();
    final h = local.hour;
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${_two(local.day)}/${_two(local.month)}/${local.year} '
        '(${_two(h12)}:${_two(local.minute)} $period)';
  }

  String get _beneficiaryLabel {
    final name = _customerName;
    final phone = _customerPhone;
    if (name == null && phone == null) {
      if (_loadingCustomer) return 'جارٍ التحميل…';
      return 'غير مرتبط بحساب';
    }
    final parts = <String>[
      if (name != null && name.trim().isNotEmpty) name.trim(),
      if (phone != null && phone.trim().isNotEmpty) phone.trim(),
    ];
    return parts.join('\n');
  }

  /// نص الإيصال المستخدم في النسخ والحفظ (عرض فقط، لا يعدّل أي بيانات).
  String get _receiptText {
    final lines = <String>[
      'NET — بيانات الحركة',
      'المبلغ: $_amountText $_currencyLabel',
      'رقم مرجع العملية: $_reference',
      'العملية: ${transactionTypeLabel(_tx.type)}',
      'الحالة: ${transactionStatusLabel(_tx.status)}',
      'تاريخ العملية: $_dateLabel',
      'المستفيد: ${_beneficiaryLabel.replaceAll('\n', ' ')}',
    ];
    return lines.join('\n');
  }

  Future<void> _copyReceipt() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _receiptText));
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'تم نسخ بيانات العملية — يمكنك لصقها للمشاركة',
          style: TextStyle(fontFamily: NetTypography.family),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveReceipt() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'net-tx-${_reference.replaceAll(RegExp(r'[^\w\-]'), '_')}.txt';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(_receiptText, flush: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ نسخة نصية: $fileName',
            style: const TextStyle(fontFamily: NetTypography.family),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر حفظ النسخة على هذا الجهاز',
            style: TextStyle(fontFamily: NetTypography.family),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final amountColor = _isInflow ? net.success : net.error;

    return NetSheet(
      title: 'بيانات الحركة',
      subtitle: 'تفاصيل عملية مسجّلة في دفتر الحسابات',
      icon: Icons.receipt_long_rounded,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.lg,
            vertical: NetSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: NetRadii.mdAll,
          ),
          child: Column(
            children: [
              Text(
                _isInflow ? 'مبلغ دائن (إضافة)' : 'مبلغ مدين (خصم)',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: NetSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _amountText,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(width: NetSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      _currencyLabel,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        _DetailRow(
          label: 'رقم مرجع العملية',
          value: _reference,
          trailing: IconButton(
            tooltip: 'نسخ المرجع',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _reference));
            },
            icon: Icon(
              Icons.copy_rounded,
              size: NetSizes.iconSm,
              color: palette.textSecondary,
            ),
          ),
        ),
        _DetailRow(label: 'العملية', value: transactionTypeLabel(_tx.type)),
        _DetailRow(
          label: 'الحالة',
          value: transactionStatusLabel(_tx.status),
          valueColor: transactionStatusColor(_tx.status, net),
        ),
        _DetailRow(label: 'تاريخ العملية', value: _dateLabel),
        _DetailRow(label: 'المستفيد', value: _beneficiaryLabel),
        const SizedBox(height: NetSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copyReceipt,
                icon: const Icon(Icons.ios_share_rounded, size: NetSizes.iconSm),
                label: const Text(
                  'مشاركة',
                  style: TextStyle(fontFamily: NetTypography.family),
                ),
              ),
            ),
            const SizedBox(width: NetSpacing.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saveReceipt,
                icon: const Icon(Icons.download_rounded, size: NetSizes.iconSm),
                label: const Text(
                  'حفظ',
                  style: TextStyle(fontFamily: NetTypography.family),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// صف تفاصيل: التسمية في جهة البداية (اليمين) والقيمة في الجهة المقابلة.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.trailing,
    this.valueColor,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NetSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                    color: valueColor ?? palette.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Divider(height: 1, color: palette.border),
      ],
    );
  }
}
