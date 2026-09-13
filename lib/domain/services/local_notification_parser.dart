import '../entities/payment_event.dart';

/// Converts a raw Android notification observation into the same domain event
/// consumed by [UnifiedPaymentEventEngine]. It deliberately performs no
/// wallet-specific or financial parsing.
final class LocalNotificationParser {
  const LocalNotificationParser();

  PaymentEvent parse({
    required String packageName,
    required String sourceKey,
    required String body,
    required DateTime receivedAt,
    String? title,
  }) {
    return PaymentEvent(
      channel: PaymentChannel.notification,
      sourceKey: sourceKey,
      body: body,
      receivedAt: receivedAt,
      title: _clean(title),
      packageName: packageName,
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
