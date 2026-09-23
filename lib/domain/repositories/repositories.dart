import '../../core/result.dart';
import '../entities/advance.dart';
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

  /// صفحة من نتائج البحث لتفادي تحميل آلاف الحسابات دفعة واحدة.
  /// [offset] صفوف تُتخطى بعد الترتيب بالاسم.
  Future<Result<List<Customer>>> searchPage(
    String query, {
    int limit = 80,
    int offset = 0,
  });

  /// اقتراح أرقام جوال بالبادئة أثناء الكتابة (بيع مباشر).
  /// يعيد أرقاماً مطبّعة مع الاسم والحالة، مرتبة بالأحدث، بدون حسابات موقوفة/مدمجة/مؤرشفة.
  /// [limit] يمنع N+1 واستعلامات ثقيلة.
  Future<Result<List<CustomerPhoneSuggestion>>> suggestPhonesByPrefix(
    String prefix, {
    int limit = 8,
  });

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
  Future<Result<List<Card>>> listAll();
  Future<Result<Set<String>>> existingSerialsAmong(Iterable<String> serials);
  Future<Result<Set<String>>> existingSecretsAmong(Iterable<String> secrets);
  Future<Result<List<Card>>> findByCategory(String categoryId);
  Future<Result<List<Card>>> findAvailableByCategory(String categoryId);
  Future<Result<Card>> reserveFirstAvailable({
    required String categoryId,
    required String reservationId,
    required DateTime reservedAt,
    required DateTime expiresAt,
  });
  Future<Result<List<Card>>> listByStatus(CardStatus status);
  Future<Result<void>> save(Card card);
  Future<Result<void>> saveAll(List<Card> cards);
  Future<Result<int>> expireReservations(DateTime now);
  Future<Result<void>> reserve(String cardId, CardReservation reservation);
  Future<Result<void>> releaseReservation(String cardId, String reservationId);
  Future<Result<void>> markSold(String cardId, String saleId);
  Future<Result<void>> restoreAvailable(String cardId);

  /// يحذف كرتاً واحداً نهائياً ويرجع عدد الصفوف المحذوفة (0 إذا لم يوجد).
  Future<Result<int>> delete(String id);

  /// يحذف مجموعة كروت ويرجع عدد الصفوف المحذوفة فعلياً.
  Future<Result<int>> deleteMany(List<String> ids);
}

abstract interface class TransactionRepository {
  Future<Result<void>> append(Transaction transaction);
  Future<Result<List<Transaction>>> findByCustomer(String customerId);
  Future<Result<Transaction?>> findByReference(String reference);
  Future<Result<List<Transaction>>> listRecent({int limit = 50});
  Future<Result<List<Transaction>>> listCompleted({String? currencyCode});
}

abstract interface class SaleRepository {
  Future<Result<void>> save(Sale sale);
  Future<Result<Sale?>> findById(String id);
  Future<Result<List<Sale>>> findByCustomer(String customerId);
  Future<Result<List<Sale>>> listRecent({int limit = 50});
  Future<Result<List<Sale>>> listCompletedBetween(DateTime from, DateTime to);
}

abstract interface class AdvanceRepository {
  Future<Result<Advance?>> findOpenByCustomer({required String customerId, required String currencyCode});
  Future<Result<List<Advance>>> listByCustomer(String customerId);
  Future<Result<Advance?>> findById(String id);
}

abstract interface class MessageRepository {
  Future<Result<void>> save(IncomingMessage message);
  Future<Result<IncomingMessage?>> findById(String id);
  Future<Result<IncomingMessage?>> findByExternalReference(String reference);
  Future<Result<List<IncomingMessage>>> pendingProcessing();
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status);
  Future<Result<int>> countByStatus(MessageProcessingStatus status);
  /// Live COUNT for a status. Emits immediately then on every table change.
  Stream<int> watchCountByStatus(MessageProcessingStatus status);
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100});
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status);
  Future<Result<void>> delete(String id);
}

abstract interface class TransferTemplateRepository {
  Future<Result<List<TransferTemplate>>> listAll();
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId);
  Future<Result<TransferTemplate?>> findById(String id);
  Future<Result<void>> save(TransferTemplate template);
  Future<Result<void>> delete(String id);
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

  /// Phase 16 — lookup by entity id, action, or payload fragment.
  Future<Result<List<AuditLog>>> search({required String query, int limit = 200});
}
