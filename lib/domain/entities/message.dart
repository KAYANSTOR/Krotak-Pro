import 'money.dart';

enum MessageProcessingStatus { received, parsed, processed, rejected, failed }

/// Classifies the extracted transfer identifier so identity resolution and
/// delivery never treat an account/name/reference as a phone number.
enum TransferIdentifierType { phone, account, reference, name, unknown }

final class TransferTemplate {
  const TransferTemplate({
    required this.id,
    required this.name,
    required this.pattern,
    required this.isActive,
  });

  final String id;
  final String name;

  /// Human pattern using either style:
  /// - `{amount}`, `{phone}`, `{account}`, `{ref}`
  /// - `%amount`, `%phone`, `%account`, `%ref`
  ///
  /// At least `{amount}`/`%amount` is required. Identifier placeholders are
  /// optional; when both phone and account appear, phone takes precedence for
  /// [TransferIdentifierType.phone], otherwise account/ref map to account/reference.
  final String pattern;
  final bool isActive;
}

final class IncomingMessage {
  const IncomingMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.status,
    this.externalReference,
    this.customerIdentifier,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final MessageProcessingStatus status;
  final String? externalReference;
  final String? customerIdentifier;
}

/// Structured parse result only — no commercial decisions, no SMS send.
final class ParsedTransfer {
  const ParsedTransfer({
    required this.messageId,
    required this.amount,
    required this.customerIdentifier,
    required this.identifierType,
    required this.reference,
    this.templateId,
    this.rawIdentifier,
  });

  final String messageId;
  final Money amount;

  /// Extracted identifier value as it appeared after normalization.
  final String customerIdentifier;

  /// Explicit classification — never inferred later from digit shape alone
  /// once the template has classified it.
  final TransferIdentifierType identifierType;

  final String reference;
  final String? templateId;

  /// Original captured token before phone/account normalization (diagnostics).
  final String? rawIdentifier;
}
