import 'money.dart';

enum MessageProcessingStatus {
  /// Message stored, not yet parsed.
  received,
  /// Fields extracted and shape accepted.
  parsed,
  /// Temporary shortfall; eligible for retry / review.
  pending,
  /// Delivery attempt in progress.
  sending,
  /// Fully processed (ledger + delivery recorded as required).
  processed,
  /// Exhausted retry policy.
  failedMaxAttempts,
  /// Rejected by a known business rule.
  rejected,
  /// Recovered from a pending/failed state and re-entered the pipeline safely.
  recovered,
  /// Legacy / generic failure (prefer failedMaxAttempts when max attempts reached).
  failed,
}

/// Classifies the extracted transfer identifier so identity resolution and
/// delivery never treat an account/name/reference as a phone number.
enum TransferIdentifierType { phone, account, reference, name, unknown }

/// How the customer is identified in the sample SMS for this template.
enum TemplateIdentifierKind {
  phone,
  alternativeNumber,
  account,
  senderNameOnly,
  balanceRequestCode,
}

final class TransferTemplate {
  const TransferTemplate({
    required this.id,
    required this.name,
    required this.pattern,
    required this.isActive,
    this.walletId,
    this.posId,
    this.priority = 0,
    this.sampleBody,
    this.senderCode,
    this.identifierKind = TemplateIdentifierKind.phone,
    this.senderNameLabel,
    this.noteLabel,
    this.requireReference = true,
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

  /// Optional link to a [Wallet] so templates can be managed per wallet.
  final String? walletId;

  /// Optional link to a [PosAccount]/[PointOfSale] so templates can be
  /// managed per point-of-sale (parallel to [walletId]).
  final String? posId;

  /// Lower value = higher precedence when multiple templates match.
  final int priority;

  /// Optional sample SMS body used in the wizard preview step.
  final String? sampleBody;

  /// Optional sender / source code shown in the wizard (e.g. JAIB).
  final String? senderCode;

  /// Preferred identifier kind chosen in the wizard (drives default placeholders).
  final TemplateIdentifierKind identifierKind;

  /// Static display label for "sender name" shown in the wizard preview.
  /// Not extracted from the message body — a fixed annotation on the
  /// template itself (e.g. "غير معروف").
  final String? senderNameLabel;

  /// Static display label for "note / statement" shown in the wizard
  /// preview (e.g. "تحويل مشترك"). Not extracted from the message body.
  final String? noteLabel;

  /// Whether a captured `{ref}` is mandatory for a successful match.
  /// Defaults to `true` — the safe, original behaviour: a template with
  /// no reference can't be de-duplicated against a real transaction.
  /// Only set `false` deliberately for message formats that genuinely
  /// carry no reference (e.g. POS card-request templates).
  final bool requireReference;

  TransferTemplate copyWith({
    String? id,
    String? name,
    String? pattern,
    bool? isActive,
    String? walletId,
    String? posId,
    int? priority,
    String? sampleBody,
    String? senderCode,
    TemplateIdentifierKind? identifierKind,
    String? senderNameLabel,
    String? noteLabel,
    bool? requireReference,
    bool clearWalletId = false,
    bool clearPosId = false,
  }) {
    return TransferTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      isActive: isActive ?? this.isActive,
      walletId: clearWalletId ? null : (walletId ?? this.walletId),
      posId: clearPosId ? null : (posId ?? this.posId),
      priority: priority ?? this.priority,
      sampleBody: sampleBody ?? this.sampleBody,
      senderCode: senderCode ?? this.senderCode,
      identifierKind: identifierKind ?? this.identifierKind,
      senderNameLabel: senderNameLabel ?? this.senderNameLabel,
      noteLabel: noteLabel ?? this.noteLabel,
      requireReference: requireReference ?? this.requireReference,
    );
  }
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
