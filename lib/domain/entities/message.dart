import 'money.dart';

enum MessageProcessingStatus { received, parsed, processed, rejected, failed }

final class TransferTemplate {
  const TransferTemplate({
    required this.id,
    required this.name,
    required this.pattern,
    required this.isActive,
  });

  final String id;
  final String name;
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

final class ParsedTransfer {
  const ParsedTransfer({
    required this.messageId,
    required this.amount,
    required this.customerIdentifier,
    required this.reference,
  });

  final String messageId;
  final Money amount;
  final String customerIdentifier;
  final String reference;
}
