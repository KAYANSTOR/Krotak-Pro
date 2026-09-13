import 'message.dart';

/// How a payment observation arrived. Commercial processing is the same
/// regardless of channel — only ingest, fingerprint and raw persistence differ.
enum PaymentChannel { sms, notification, manual }

/// Logical wallet / origin that produced the observation.
final class PaymentSource {
  const PaymentSource({
    required this.id,
    required this.displayName,
    required this.channel,
    this.packageName,
    this.smsSenderHint,
    this.enabled = true,
  });

  final String id;
  final String displayName;
  final PaymentChannel channel;
  final String? packageName;
  final String? smsSenderHint;
  final bool enabled;
}

/// Raw inbound payment observation before parse / commercial decisions.
final class PaymentEvent {
  const PaymentEvent({
    required this.channel,
    required this.sourceKey,
    required this.body,
    required this.receivedAt,
    this.title,
    this.packageName,
  });

  final PaymentChannel channel;
  final String sourceKey;
  final String body;
  final DateTime receivedAt;
  final String? title;
  final String? packageName;

  IncomingMessage toProvisionalMessage({required String id}) {
    return IncomingMessage(
      id: id,
      sender: sourceKey,
      body: _combinedBody,
      receivedAt: receivedAt,
      status: MessageProcessingStatus.received,
    );
  }

  String get _combinedBody {
    final title = this.title?.trim();
    if (title == null || title.isEmpty) return body;
    return '$title\n$body';
  }
}

/// Stable idempotency key for a payment observation.
final class PaymentFingerprint {
  const PaymentFingerprint({
    required this.key,
    required this.version,
    required this.strategy,
  });

  final String key;
  final String version;
  final String strategy;
}

/// Result of ingest before / after TransferProcessor.
final class PaymentIngestResult {
  const PaymentIngestResult({
    required this.fingerprint,
    required this.duplicate,
    this.message,
    this.parsed,
  });

  final PaymentFingerprint fingerprint;
  final bool duplicate;
  final IncomingMessage? message;
  final ParsedTransfer? parsed;
}
