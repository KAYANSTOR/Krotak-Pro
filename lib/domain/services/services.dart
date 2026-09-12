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

  /// Total outstanding balance across all customers for [currencyCode].
  /// Single query path — no per-customer loop.
  Future<Result<Money>> getTotalOutstanding({required String currencyCode});

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

enum ManualSaleMethod { cash, credit }

abstract interface class SaleService {
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
    String? operationId,
  });

  /// Manual direct sale from operator UI (phone + amount + name + cash/credit).
  ///
  /// Resolves or creates the customer by phone, matches an active category by
  /// face value == [amount], sells one FIFO card, and:
  /// - [ManualSaleMethod.cash]: credits deposit then sale (net debt unchanged)
  /// - [ManualSaleMethod.credit]: sale only (creates customer debt; no pre-balance required)
  Future<Result<Sale>> sellManual({
    required String phone,
    required String displayName,
    required Money amount,
    required ManualSaleMethod method,
    String? operationId,
  });

  Future<Result<Sale>> reverseSale({required String saleId});
}

/// Narrow application boundary used after SMS delivery has succeeded.
/// It completes an already-reserved card without performing a second
/// reservation, keeping the financial commit separate from delivery.
abstract interface class ReservedSaleService {
  Future<Result<Sale>> completeReservedSale({
    required String customerId,
    required String cardId,
    required String reservationId,
    required String operationId,
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
