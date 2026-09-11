import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/license.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../entities/wallet.dart';

abstract interface class CustomerRepository {
  Future<Result<Customer?>> findById(String id);
  Future<Result<Customer?>> findByIdentifier(String value);
  Future<Result<List<Customer>>> search(String query);
  Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId);
  Future<Result<void>> save(Customer customer);
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier);
}

abstract interface class WalletRepository {
  Future<Result<Wallet?>> findById(String id);
  Future<Result<List<Wallet>>> listAll();
  Future<Result<void>> save(Wallet wallet);
}

abstract interface class PointOfSaleRepository {
  Future<Result<PointOfSale?>> findById(String id);
  Future<Result<List<PointOfSale>>> listAll();
  Future<Result<void>> save(PointOfSale pointOfSale);
}

abstract interface class CardCategoryRepository {
  Future<Result<CardCategory?>> findById(String id);
  Future<Result<List<CardCategory>>> listAll();
  Future<Result<void>> save(CardCategory category);
}

abstract interface class CardRepository {
  Future<Result<Card?>> findById(String id);
  Future<Result<Card?>> findBySerialNumber(String serialNumber);
  Future<Result<List<Card>>> findByCategory(String categoryId);
  Future<Result<List<Card>>> findAvailableByCategory(String categoryId);
  Future<Result<List<Card>>> listByStatus(CardStatus status);
  Future<Result<void>> save(Card card);
  Future<Result<int>> expireReservations(DateTime now);
  Future<Result<void>> reserve(String cardId, CardReservation reservation);
  Future<Result<void>> releaseReservation(String cardId, String reservationId);
  Future<Result<void>> markSold(String cardId, String saleId);
  Future<Result<void>> restoreAvailable(String cardId);
}

abstract interface class TransactionRepository {
  Future<Result<void>> append(Transaction transaction);
  Future<Result<List<Transaction>>> findByCustomer(String customerId);
  Future<Result<Transaction?>> findByReference(String reference);
  Future<Result<List<Transaction>>> listRecent({int limit = 50});
}

abstract interface class SaleRepository {
  Future<Result<void>> save(Sale sale);
  Future<Result<Sale?>> findById(String id);
  Future<Result<List<Sale>>> findByCustomer(String customerId);
  Future<Result<List<Sale>>> listRecent({int limit = 50});
  Future<Result<List<Sale>>> listCompletedBetween(DateTime from, DateTime to);
}

abstract interface class MessageRepository {
  Future<Result<void>> save(IncomingMessage message);
  Future<Result<IncomingMessage?>> findById(String id);
  Future<Result<IncomingMessage?>> findByExternalReference(String reference);
  Future<Result<List<IncomingMessage>>> pendingProcessing();
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status);
}

abstract interface class LicenseRepository {
  Future<Result<License?>> getCurrent();
  Future<Result<void>> save(License license);
}

abstract interface class SettingsRepository {
  Future<Result<AppSetting?>> find(String key);
  Future<Result<void>> save(AppSetting setting);
}

abstract interface class AuditLogRepository {
  Future<Result<void>> append(AuditLog log);
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId);
}
