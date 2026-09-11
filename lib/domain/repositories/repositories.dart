import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../entities/wallet.dart';
import '../../core/result.dart';

abstract interface class CustomerRepository {
  Future<Result<Customer>> getById(String id);
  Future<Result<Customer?>> findByPhone(String phone);
  Future<Result<List<Customer>>> list({int limit = 50, int offset = 0});
  Future<Result<Customer>> save(Customer customer);
}

abstract interface class WalletRepository {
  Future<Result<Wallet>> getById(String id);
  Future<Result<Wallet?>> findByCustomerAndCurrency(String customerId, String currencyCode);
  Future<Result<Wallet>> save(Wallet wallet);
}

abstract interface class CardCategoryRepository {
  Future<Result<CardCategory>> getById(String id);
  Future<Result<List<CardCategory>>> listActive();
  Future<Result<CardCategory>> save(CardCategory category);
}

abstract interface class CardInventoryRepository {
  Future<Result<Card>> getById(String id);
  Future<Result<Card?>> findBySerial(String serial);
  Future<Result<List<Card>>> listAvailable(String categoryId, {int limit = 20});
  Future<Result<Card>> save(Card card);
}

abstract interface class MessageRepository {
  Future<Result<Message>> getById(String id);
  Future<Result<Message?>> findByDedupeKey(String dedupeKey);
  Future<Result<Message>> save(Message message);
}

abstract interface class TransactionRepository {
  Future<Result<Transaction>> getById(String id);
  Future<Result<List<Transaction>>> listByCustomer(String customerId, {int limit = 50});
  Future<Result<Transaction>> save(Transaction transaction);
}

abstract interface class AuditRepository {
  Future<Result<void>> append(AuditLog entry);
}

abstract interface class SettingRepository {
  Future<Result<AppSetting?>> get(String key);
  Future<Result<void>> set(AppSetting setting);
}
