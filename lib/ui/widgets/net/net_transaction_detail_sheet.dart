import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../errors/user_facing_error_localizer.dart';
import '../../services/receipt_image_service.dart';
import 'transaction_receipt_card.dart';
import '../../labels/net_labels.dart';
import '../async_views.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import 'net_sheet.dart';

/// تفاصيل العملية — مطابقة تخطيط إطار «بيانات الحركة» في التطبيق المرجعي
/// (رأس، مبلغ مميّز، صفوف تفاصيل، إجراءا مشاركة/حفظ) مع مسميات NET وألوانها.
///
/// نص الإيصال مُستخرج في [buildTransactionReceiptText] ليكون قابلاً للاختبار
/// مستقلاً عن الواجهة.
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

  /// WP-8 — مفتاح حدود الرسم لبطاقة الإشعار (PNG).
  final GlobalKey _receiptKey = GlobalKey();

  static const ReceiptImageService _imageService = ReceiptImageService();

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

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontFamily: NetTypography.family)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// WP-8 — مشاركة **صورة** الإشعار (لا نص) عبر ورقة النظام.
  Future<void> _shareReceipt() async {
    final bytes = await _imageService.capture(_receiptKey);
    if (bytes == null) {
      _notice('تعذر إنشاء صورة الإشعار. حاول مرة أخرى.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, ReceiptImageService.fileNameFor(_reference)));
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'إشعار عملية',
      );
    } catch (error) {
      _notice(localizedError(error));
    }
  }

  /// WP-8/D5 — حفظ صورة الإشعار في `Pictures/Krotak Pro/` (بلا حفظ TXT).
  Future<void> _saveReceipt() async {
    final bytes = await _imageService.capture(_receiptKey);
    if (bytes == null) {
      _notice('تعذر إنشاء صورة الإشعار. حاول مرة أخرى.');
      return;
    }
    final c = AppScope.of(context);
    final saved = await c.visibleStorage.saveImageToPictures(
      bytes: bytes,
      fileName: ReceiptImageService.fileNameFor(_reference),
    );
    if (saved is Failure<String>) {
      _notice(localizedError(saved.error));
      return;
    }
    _notice('تم حفظ صورة الإشعار في الصور: ${(saved as Success<String>).value}');
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
        RepaintBoundary(
          key: _receiptKey,
          child: TransactionReceiptCard(
            amountText: _amountText,
            currencyLabel: _currencyLabel,
            reference: _reference,
            typeLabel: transactionTypeLabel(_tx.type),
            statusLabel: transactionStatusLabel(_tx.status),
            dateLabel: _dateLabel,
            beneficiaryLabel: _beneficiaryLabel,
            isInflow: _isInflow,
            statusColor: transactionStatusColor(_tx.status, net),
            onCopyReference: () async {
              await Clipboard.setData(ClipboardData(text: _reference));
            },
          ),
        ),
        const SizedBox(height: NetSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareReceipt,
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

/// نص إيصال العملية — دالة نقية قابلة للاختبار بدون واجهة.
///
/// تُشترك فيها زرّي «مشاركة» و«حفظ»، فأي تعديل في الصيغة يظهر في الاثنين.
String buildTransactionReceiptText({
  required String amountText,
  required String currencyLabel,
  required String reference,
  required String typeLabel,
  required String statusLabel,
  required String dateLabel,
  required String beneficiaryLabel,
}) {
  return <String>[
    'NET — بيانات الحركة',
    'المبلغ: $amountText $currencyLabel',
    'رقم مرجع العملية: $reference',
    'العملية: $typeLabel',
    'الحالة: $statusLabel',
    'تاريخ العملية: $dateLabel',
    'المستفيد: ${beneficiaryLabel.replaceAll('\n', ' ')}',
  ].join('\n');
}
