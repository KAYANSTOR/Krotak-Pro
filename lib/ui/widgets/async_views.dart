import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';

/// Shared loading indicator for list/detail bodies.
///
/// Set [skeleton] to render layout-shaped placeholders instead of a spinner.
class AsyncLoadingView extends StatelessWidget {
  const AsyncLoadingView({
    super.key,
    this.message = 'جاري التحميل…',
    this.skeleton = false,
    this.skeletonCount = 4,
  });

  final String message;
  final bool skeleton;
  final int skeletonCount;

  @override
  Widget build(BuildContext context) {
    if (skeleton) return NetSkeletonList(count: skeletonCount);

    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
          ),
          const SizedBox(height: NetSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: NetTypography.family,
              color: cs.onSurfaceVariant,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single shimmerless skeleton block (kept animation-free so the UI stays
/// calm and predictable on low-end devices).
class NetSkeletonBox extends StatelessWidget {
  const NetSkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = NetRadii.xs,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for a list of records: icon badge + title line + subtitle line.
class NetSkeletonList extends StatelessWidget {
  const NetSkeletonList({super.key, this.count = 4, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return ListView.separated(
      padding: padding ?? NetSpacing.screen,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: NetSpacing.md),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(NetSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: NetRadii.mdAll,
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            const NetSkeletonBox(width: 42, height: 42, radius: NetRadii.sm),
            const SizedBox(width: NetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  NetSkeletonBox(width: 150, height: 13),
                  SizedBox(height: NetSpacing.sm),
                  NetSkeletonBox(width: 96, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for card grids (dashboard KPI tiles, inventory categories).
class NetSkeletonGrid extends StatelessWidget {
  const NetSkeletonGrid({super.key, this.count = 4, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding ?? NetSpacing.pageH,
      mainAxisSpacing: NetSpacing.md,
      crossAxisSpacing: NetSpacing.md,
      childAspectRatio: 1.55,
      children: List<Widget>.generate(
        count,
        (_) => Container(
          padding: const EdgeInsets.all(NetSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: NetRadii.mdAll,
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              NetSkeletonBox(width: 44, height: 44, radius: NetRadii.sm),
              SizedBox(height: NetSpacing.md),
              NetSkeletonBox(width: 92, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class AsyncEmptyView extends StatelessWidget {
  const AsyncEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.hint,
    this.compact = false,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? hint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? NetSpacing.lg : NetSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: KayanColors.primary),
            ),
            const SizedBox(height: NetSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: palette.textPrimary,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: NetSpacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: NetSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'تعذر إكمال العملية',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NetSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: palette.isDark ? 0.22 : 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 34, color: errorColor),
            ),
            const SizedBox(height: NetSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: NetSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: NetSizes.iconSm),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact inline status strip used inside scrollables (no centering).
class NetInlineNotice extends StatelessWidget {
  const NetInlineNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
    this.onTap,
  });

  final String message;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final tint = color ?? KayanColors.primary;
    return Padding(
      padding: NetSpacing.pageH,
      child: Material(
        color: tint.withValues(alpha: palette.isDark ? 0.18 : 0.08),
        borderRadius: NetRadii.smAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: NetRadii.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: NetSizes.iconSm, color: tint),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_left_rounded, size: NetSizes.iconSm, color: tint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formats minor units for display (YER default).
String formatMoneyMinor(int minorUnits, {String currency = 'ر.ي'}) {
  return formatMinorValue(minorUnits / 100.0, currency: currency);
}

/// Formats an already-converted major amount (used by animated counters).
String formatMinorValue(double major, {String currency = 'ر.ي'}) {
  final text = major == major.roundToDouble()
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
  return '$text $currency';
}

/// Amount only (no currency suffix) — for counters that render the currency
/// as a separate, smaller text run.
String formatAmountOnly(num major) {
  final value = major.toDouble();
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
