import 'package:flutter/material.dart';

import '../../../domain/entities/transaction.dart';
import '../../labels/net_labels.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../async_views.dart';

/// Row used by the dashboard "آخر العمليات" list.
///
/// Arabic labels come from [net_labels] instead of leaking enum names, and the
/// status is expressed with color + icon + text (never color alone).
class NetRecentTransactionCard extends StatelessWidget {
  const NetRecentTransactionCard({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  bool get _isInflow =>
      transaction.type == TransactionType.deposit ||
      transaction.type == TransactionType.reward;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final statusColor = transactionStatusColor(transaction.status, net);
    final statusBg = transactionStatusContainer(transaction.status, net);
    final typeLabel = transactionTypeLabel(transaction.type);
    final amountMajor = transaction.amount.minorUnits / 100.0;
    final amountText = amountMajor == amountMajor.roundToDouble()
        ? amountMajor.toStringAsFixed(0)
        : amountMajor.toStringAsFixed(2);
    final sign = _isInflow ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.lg,
        vertical: NetSpacing.xs,
      ),
      child: Material(
        color: palette.surface,
        borderRadius: NetRadii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: NetRadii.mdAll,
          child: Container(
            padding: const EdgeInsets.all(NetSpacing.md),
            decoration: BoxDecoration(
              borderRadius: NetRadii.mdAll,
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: NetSizes.badge,
                  height: NetSizes.badge,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: palette.isDark ? 0.22 : 0.12),
                    borderRadius: NetRadii.smAll,
                  ),
                  child: Icon(
                    transactionTypeIcon(transaction.type),
                    size: 20,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: NetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        typeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            relativeArabicTime(transaction.createdAt),
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 11.5,
                              color: palette.textSecondary,
                            ),
                          ),
                          if ((transaction.reference ?? '').isNotEmpty) ...[
                            Text(
                              ' · ',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 11.5,
                                color: palette.textTertiary,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                transaction.reference!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontSize: 11.5,
                                  color: palette.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$sign$amountText ر.ي',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _isInflow ? net.success : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NetSpacing.sm,
                        vertical: NetSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: NetRadii.pillAll,
                      ),
                      child: Text(
                        transactionStatusLabel(transaction.status),
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
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

  /// Kept for callers that only need the formatted amount.
  String get formattedAmount => formatMoneyMinor(transaction.amount.minorUnits);
}
