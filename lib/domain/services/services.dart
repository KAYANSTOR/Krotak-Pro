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

abstract interface class SaleService {
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
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
  Future<Result<ParsedTransfer?>> parse(IncomingMessage message);
}

abstract interface class TransferProcessor {
  Future<Result<void>> process(IncomingMessage message);
}

abstract interface class CustomerIdentityResolver {
  Future<Result<ResolvedIdentity>> resolve({
    required String rawIdentifier,
    TransferIdentifierType? preferredType,
  });
}

abstract interface class LicenseService {
  Future<Result<License>> current();
  Future<Result<License>> activateOffline({required String code});
}

abstract interface class BackupService {
  Future<Result<String>> exportBackup();
  Future<Result<void>> restoreBackup(String payload);
}

abstract interface class MessageRecoveryService {
  Future<Result<int>> recoverPending();
}

abstract interface class SettlementService {
  Future<Result<void>> settlePointOfSale({
    required String pointOfSaleId,
    required Money amount,
    String? reference,
  });
}

abstract interface class AccountMergeService {
  Future<Result<void>> merge({
    required String sourceCustomerId,
    required String targetCustomerId,
  });
}

final class CardImportDraft {
  const CardImportDraft({
    required this.serialNumber,
    required this.secretCode,
  });

  final String serialNumber;
  final String secretCode;
}

final class ParsedTransfer {
  const ParsedTransfer({
    required this.amount,
    required this.rawIdentifier,
    this.identifierType,
    this.reference,
    this.walletHint,
  });

  final Money amount;
  final String rawIdentifier;
  final TransferIdentifierType? identifierType;
  final String? reference;
  final String? walletHint;
}

final class ResolvedIdentity {
  const ResolvedIdentity({
    required this.customerId,
    required this.deliveryPhone,
    this.identifierId,
  });

  final String customerId;
  final String deliveryPhone;
  final String? identifierId;
}

enum TransferIdentifierType { phone, account, reference, name }
