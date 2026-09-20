import 'money.dart';

enum MessageProcessingStatus {
  received,
  parsed,
  pending,
  sending,
  processed,
  failedMaxAttempts,
  rejected,
  recovered,
  failed,
}

enum TransferIdentifierType { phone, account, reference, name, unknown }

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
  final String pattern;
  final bool isActive;
  final String? walletId;
  final String? posId;
  final int priority;
  final String? sampleBody;
  final String? senderCode;
  final TemplateIdentifierKind identifierKind;
  final String? senderNameLabel;
  final String? noteLabel;
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

final class ParsedTransfer {
  const ParsedTransfer({
    required this.messageId,
    required this.amount,
    required this.customerIdentifier,
    required this.identifierType,
    required this.reference,
    this.templateId,
    this.rawIdentifier,
    this.quantity = 1,
    this.deliveryOverride,
    this.instantCharge = false,
  });

  final String messageId;
  final Money amount;
  final String customerIdentifier;
  final TransferIdentifierType identifierType;
  final String reference;
  final String? templateId;
  final String? rawIdentifier;
  final int quantity;
  final String? deliveryOverride;
  final bool instantCharge;
}
