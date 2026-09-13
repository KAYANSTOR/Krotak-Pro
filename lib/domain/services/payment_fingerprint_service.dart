import '../entities/message.dart';
import '../entities/payment_event.dart';

/// Builds a source-agnostic idempotency fingerprint.
///
/// Policy (v1):
/// 1. Prefer bank/wallet operation reference when the parser extracted one.
/// 2. Otherwise fall back to canonical source + amount + identifier + body.
/// Channel is NOT part of the key so an SMS and a notification that carry
/// the same wallet reference collapse to one commercial event.
final class PaymentFingerprintService {
  const PaymentFingerprintService();

  static const version = 'v1';

  PaymentFingerprint compute({
    required PaymentEvent event,
    ParsedTransfer? parsed,
  }) {
    final source = _canonicalize(event.sourceKey);
    if (parsed != null) {
      final reference = _canonicalize(parsed.reference);
      if (reference.isNotEmpty) {
        return PaymentFingerprint(
          key: 'pay:$version:ref:$source:$reference',
          version: version,
          strategy: 'reference',
        );
      }
      final ident = _canonicalize(parsed.customerIdentifier);
      final amount = parsed.amount.minorUnits.toString();
      final currency = parsed.amount.currencyCode;
      return PaymentFingerprint(
        key: 'pay:$version:amt:$source:$currency:$amount:$ident:${_canonicalize(event.body)}',
        version: version,
        strategy: 'amount_identity_body',
      );
    }

    return PaymentFingerprint(
      key: 'pay:$version:body:$source:${_canonicalize(event.body)}',
      version: version,
      strategy: 'raw_body',
    );
  }

  String _canonicalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
