if (row.isProvisional || !row.hasPhone) ...[
            const SizedBox(height: NetSpacing.sm),
            Row(
              children: [
                if (row.isProvisional)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NetSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: net.warningContainer,
                      borderRadius: NetRadii.xsAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 12, color: net.warning),
                        const SizedBox(width: NetSpacing.xs),
                        Text(
                          'دفتر مؤقت',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: net.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (row.isProvisional && !row.hasPhone)
                  const SizedBox(width: NetSpacing.xs),
                if (!row.hasPhone)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NetSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: net.errorContainer,
                      borderRadius: NetRadii.xsAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off_rounded, size: 12, color: net.rejected),
                        const SizedBox(width: NetSpacing.xs),
                        Text(
                          'غير مربوط',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: net.rejected,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(
                  'اضغط للتفاصيل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: palette.textTertiary,
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  size: NetSizes.iconSm,
                  color: palette.textTertiary,
                ),
              ],
            ),
          ],