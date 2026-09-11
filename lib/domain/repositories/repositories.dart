import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/license.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../../core/result.dart';

abstract interface class CustomerRepository {
  Future<Result<Customer?>> findById(String id);
  Future<Result<Customer?>> findByIdentifier(String value);
  Future<Result<List<Customer>>> search(String query);
  Future<Result<void>> save(Customer customer);
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier);
}

abstract interface class CardRepository {
  Future<Result<Card?>> findById(String id);
  Future<Result<List<Card>>> findAvailableByCategory(String categoryId);
  Future<Result<void>> reserve(String cardId, CardReservation reservation);
  Future<Result<void>> releaseReservation(String cardId, String reservationId);
  Future<Result<void>> markSold(String cardId, String saleId);
}

abstract interface class TransactionRepository {
  Future<Result<void>> append(Transaction transaction);
  Future<Result<List<Transaction>>> findByCustomer(String customerId);
  Future<Result<Transaction?>> findByReference(String reference);
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
