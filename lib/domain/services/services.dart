import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/broadcast.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
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

  Future<Result<void>> bindPrimaryGsm({
    required String customerId,
    required String phone,
  });
}

abstract interface class CustomerBalanceService {
  Future<Result<Money>> getBalance({required String customerId, required String currencyCode});
  Future<Result<Money>> getTotalOutstanding({required String currencyCode});
  Future<Result<Transaction>> credit({required String customerId, required Money amount, String? reference});
}

abstract interface class CardCatalogService {
  Future<Result<CardCategory>> saveCategory(CardCategory category);
  Future<Result<int>> importCards({required String categoryId, required List<CardImportDraft> drafts});
}

abstract interface class WalletCatalogService {
  Future<Result<List<Wallet>>> listEnriched();

  Future<Result<Wallet>> saveWallet({
    required String name,
    String? senderId,
    WalletSourceMode sourceMode = WalletSourceMode.sms,
    String? packageName,
  });

  Future<Result<Wallet>> updateWallet({
    required String id,
    required String name,
    required WalletStatus status,
    String? senderId,
    WalletSourceMode? sourceMode,
    String? packageName,
  });

  /// Seeds the four standard Yemen wallets with correct packages/modes.
  Future<Result<void>> ensureDefaultWallets();
}

abstract interface class PointOfSaleCatalogService {
  Future<Result<PointOfSale>> savePointOfSale({required String name});
  Future<Result<PointOfSale>> updatePointOfSale({
    required String id,
    required String name,
    required PointOfSaleStatus status,
  });
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

enum ManualSaleMethod { cash, credit, gift, pos }

abstract interface class SaleService {
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
    required String operationId,
  });
  Future<Result<Sale>> sellManual({
    required String phone,
    required String displayName,
    required Money amount,
    required ManualSaleMethod method,
    String? operationId,
  });
  Future<Result<Sale>> reverseSale({required String saleId});
}

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
  Future<Result<void>> send({required String destination, required String body});
}

abstract interface class TransferProcessor {
  Future<Result<Transaction>> process(ParsedTransfer transfer);
}

abstract interface class PaymentEventEngine {
  Future<Result<Transaction?>> ingest(PaymentEvent event);
}

abstract interface class LicenseService {
  Future<Result<void>> verifyOnline();
}

abstract interface class BroadcastService {
  Future<Result<BroadcastPreview>> preview({required String body});
  Future<Result<BroadcastJob>> confirm({
    required String body,
    required String confirmationPhrase,
  });
  Future<Result<BroadcastJob>> run(
    String jobId, {
    void Function(BroadcastProgress progress)? onProgress,
  });
  Future<Result<BroadcastJob>> pause(String jobId);
  Future<Result<BroadcastJob>> cancel(String jobId);
  Future<Result<List<BroadcastJob>>> listJobs();
}

abstract interface class AdvanceService {
  Future<Result<AdvanceIssue>> request({
    required String customerId,
    required String currencyCode,
    required String operationId,
  });
  Future<Result<AdvanceIssue>> requestByIdentifier({
    required String identifier,
    required String currencyCode,
    required String operationId,
  });
  Future<Result<AdvancePaymentResult>> applyPayment({
    required String customerId,
    required Money amount,
    required String reference,
  });
  Future<Result<List<Advance>>> listCustomerAdvances(String customerId);
}

/// How card stock lines are structured at import time.
enum CardImportFormat {
  /// Serial + PIN/secret required.
  serialAndPin,
  /// Serial only (PIN-less voucher).
  serialOnly,
}

final class CardImportDraft {
  const CardImportDraft({
    required this.serialNumber,
    required this.secretCode,
    this.format = CardImportFormat.serialAndPin,
  });
  final String serialNumber;
  /// Empty when [format] is [CardImportFormat.serialOnly].
  final String secretCode;
  final CardImportFormat format;

  bool get hasSecret => secretCode.trim().isNotEmpty;
}

/// Builds customer SMS body for a delivered voucher.
/// Serial-only cards omit the PIN line.
String cardDeliverySmsBody({required String serialNumber, required String secretCode}) {
  final serial = serialNumber.trim();
  final secret = secretCode.trim();
  if (secret.isEmpty) {
    return 'بطاقة الإنترنت\nالرقم: $serial';
  }
  return 'بطاقة الإنترنت\nالرقم: $serial\nالرمز: $secret';
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
