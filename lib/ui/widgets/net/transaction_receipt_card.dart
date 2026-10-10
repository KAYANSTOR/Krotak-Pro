import 'package:flutter/material.dart';

import '../../../core/app_brand.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// WP-8 — بطاقة إشعار العملية: تنسيق عربي RTL مستقل عن أي شاشة.
///
/// تُستعمل كمصدر واحد لصورة الإشعار (PNG) في:
/// - «حفظ» → `Pictures/Krotak Pro/إشعار-<المرجع>.png` (D5).
/// - «مشاركة» → مشاركة ملف صورة عبر `share_plus` (لا نص).
///
/// البطاقة عرض فقط: لا تقرأ ولا تكتب أي بيانات.
class TransactionReceiptCard extends StatelessWidget {
  const TransactionReceiptCard({
    super.key,
    required this.amountText,
    required this.currencyLabel,
    required this.reference,
    required this.typeLabel,
    required this.statusLabel,
    required this.dateLabel,
    required this.beneficiaryLabel,
    required this.isInflow,
    this.statusColor,
    this.onCopyReference,
  });

  final String amountText;
  final String currencyLabel;
  final String reference;
  final String typeLabel;
  final String statusLabel;
  final String dateLabel;
  final String beneficiaryLabel;

  /// موجب (دائن) أو سالب (مدين) — يحدّد لون المبلغ ووصفه.
  final bool isInflow;

  final Color? statusColor;

  /// إجراء نسخ المرجع (يبقى منفصلاً عن الحفظ/المشاركة).
  final VoidCallback? onCopyReference;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final amountColor = isInflow ? palette.primary : palette.textPrimary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: palette.surface,
        padding: const EdgeInsets.all(NetSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  AppBrand.latinName,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: palette.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  'بيانات الحركة',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NetSpacing.sm),
            Container(
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
                    isInflow ? 'مبلغ دائن (إضافة)' : 'مبلغ مدين (خصم)',
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
                        amountText,
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
                          currencyLabel,
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
            const SizedBox(height: NetSpacing.sm),
            _ReceiptRow(
              label: 'رقم مرجع العملية',
              value: reference,
              trailing: onCopyReference == null
                  ? null
                  : IconButton(
                      tooltip: 'نسخ المرجع',
                      onPressed: onCopyReference,
                      icon: Icon(
                        Icons.copy_rounded,
                        size: NetSizes.iconSm,
                        color: palette.textSecondary,
                      ),
                    ),
            ),
            _ReceiptRow(label: 'العملية', value: typeLabel),
            _ReceiptRow(
              label: 'الحالة',
              value: statusLabel,
              valueColor: statusColor,
            ),
            _ReceiptRow(label: 'تاريخ العملية', value: dateLabel),
            _ReceiptRow(label: 'المستفيد', value: beneficiaryLabel),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
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
