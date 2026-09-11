import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';

abstract interface class CardInventoryService {
  Future<Result<Card>> reserveAvailableCard({
    required String categoryId,
    required String reservationId,
    required DateTime now,
    required DateTime expiresAt,
  });

  Future<Result<void>> releaseReservation({
    required String cardId,
    required String reservationId,
  });
}

abstract interface class MessageParser {
  Result<ParsedTransfer> parse(IncomingMessage message);
}

abstract interface class MessageSender {
  Future<Result<void>> send({
    required String destination,
    required String body,
  });
}

abstract interface class TransferProcessor {
  Future<Result<Transaction>> process(ParsedTransfer transfer);
}

abstract interface class LicenseService {
  Future<Result<void>> verifyOnline();
}

final class UnresolvedDomainDecision implements Exception {
  const UnresolvedDomainDecision(this.decision);

  final String decision;
}

final class TransferProcessingInput {
  const TransferProcessingInput({
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
