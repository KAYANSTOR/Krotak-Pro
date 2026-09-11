import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../entities/wallet.dart';

abstract interface class CustomerService {
  Future<Result<Customer>> create({
    required String displayName,
    required CustomerIdentifierType identifierType,
    required String identifierValue,
  });

  Future<Result<void>> blacklist(String customerId);

  Future<Result<void>> addIdentifier({
    required String customerId,
    required CustomerIdentifierType type,
    required String value,
    required bool isPrimary,
  });
}

abstract interface class CustomerBalanceService {
  Future<Result<Money>> getBalance({
    required String customerId,
    required String currencyCode,
  });

  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
  });
}

abstract interface class CardCatalogService {
  Future<Result<CardCategory>> saveCategory(CardCategory category);

  Future<Result<int>> importCards({
    required String categoryId,
    required List<CardImportDraft> drafts,
  });
}

abstract interface class WalletCatalogService {
  Future<Result<Wallet>> saveWallet({required String name});
}

abstract interface class PointOfSaleCatalogService {
  Future<Result<PointOfSale>> savePointOfSale({required String name});
}

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

abstract interface class SaleService {
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
    String? operationId,
  });

  /// Completes a sale for a card that has already been reserved by the
  /// transfer flow. No second reservation is performed.
  Future<Result<Sale>> completeReservedSale({
    required String customerId,
    required String cardId,
    required String reservationId,
    required String operationId,
  });

  Future<Result<Sale>> reverseSale({required String saleId});
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

final class CardImportDraft {
  const CardImportDraft({
    required this.serialNumber,
    required this.secretCode,
  });

  final String serialNumber;
  final String secretCode;
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
