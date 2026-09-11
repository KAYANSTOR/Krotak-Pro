import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';

/// Shared loading indicator for list/detail bodies.
class AsyncLoadingView extends StatelessWidget {
  const AsyncLoadingView({super.key, this.message = 'جاري التحميل…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              color: KayanColors.textSecondary,
            ),
          ),
        ],
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
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: KayanColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                color: KayanColors.textSecondary,
                fontSize: 15,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
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
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: KayanColors.warning),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                color: KayanColors.textPrimary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Formats minor units for display (YER default).
String formatMoneyMinor(int minorUnits, {String currency = 'ر.ي'}) {
  final major = minorUnits / 100.0;
  final text = major == major.roundToDouble()
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
  return '$text $currency';
}
