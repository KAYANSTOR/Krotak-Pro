import 'package:drift/drift.dart';

import '../../core/result.dart';
import '../../domain/entities/audit.dart' as domain;
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart' as domain;
import '../../domain/entities/license.dart' as domain;
import '../../domain/entities/message.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart' as domain;
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/wallet.dart' as domain;
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

final class LocalCustomerRepository implements CustomerRepository {
  const LocalCustomerRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.Customer?>> findById(String id) async {
    try {
      final query = database.select(database.customers)
        ..where((table) => table.id.equals(id));
      final row = await query.getSingleOrNull();
      return Success(row == null ? null : _toCustomer(row));
    } catch (error) {
      return Failure(_failure('customer_find_failed', error));
    }
  }

  @override
  Future<Result<domain.Customer?>> findByIdentifier(String value) async {
    try {
      final identifierQuery = database.select(database.customerIdentifiers)
        ..where((table) => table.value.equals(value));
      final identifier = await identifierQuery.getSingleOrNull();
      if (identifier == null) return const Success(null);

      final customer = await findById(identifier.customerId);
      if (customer is Failure<domain.Customer?>) return customer;
      return customer;
    } catch (error) {
      return Failure(_failure('customer_identifier_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Customer>>> search(String query) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) {
        final rows = await (database.select(database.customers)
              ..orderBy([(table) => OrderingTerm(expression: table.displayName)]))
            .get();
        return Success(rows.map(_toCustomer).toList(growable: false));
      }

      final byName = await (database.select(database.customers)
            ..where((table) => table.displayName.contains(trimmed)))
          .get();
      final identifiers = await (database.select(database.customerIdentifiers)
            ..where((table) => table.value.contains(trimmed)))
          .get();
      final ids = <String>{
        ...byName.map((row) => row.id),
        ...identifiers.map((row) => row.customerId),
      };
      if (ids.isEmpty) {
        return const Success(<domain.Customer>[]);
      }

      final rows = await (database.select(database.customers)
            ..where((table) => table.id.isIn(ids))
            ..orderBy([(table) => OrderingTerm(expression: table.displayName)]))
          .get();
      return Success(rows.map(_toCustomer).toList(growable: false));
    } catch (error) {
      return Failure(_failure('customer_search_failed', error));
    }
  }

  @override
  Future<Result<List<domain.CustomerIdentifier>>> listIdentifiers(
    String customerId,
  ) async {
    try {
      final rows = await (database.select(database.customerIdentifiers)
            ..where((table) => table.customerId.equals(customerId)))
          .get();
      return Success(rows.map(_toIdentifier).toList(growable: false));
    } catch (error) {
      return Failure(_failure('customer_identifiers_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.Customer customer) async {
    try {
      await database.into(database.customers).insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: customer.id,
              displayName: customer.displayName,
              status: customer.status.name,
              mergedIntoId: Value(customer.mergedIntoId),
              createdAt: customer.createdAt,
              updatedAt: customer.updatedAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('customer_save_failed', error));
    }
  }

  @override
  Future<Result<void>> saveIdentifier(domain.CustomerIdentifier identifier) async {
    try {
      await database.transaction(() async {
        if (identifier.isPrimary) {
          await (database.update(database.customerIdentifiers)
                ..where((table) => table.customerId.equals(identifier.customerId)))
              .write(
            const CustomerIdentifiersCompanion(isPrimary: Value(false)),
          );
        }
        await database.into(database.customerIdentifiers).insertOnConflictUpdate(
              CustomerIdentifiersCompanion.insert(
                id: identifier.id,
                customerId: identifier.customerId,
                type: identifier.type.name,
                value: identifier.value,
                isPrimary: Value(identifier.isPrimary),
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(_failure('customer_identifier_save_failed', error));
    }
  }

  domain.Customer _toCustomer(Customer row) {
    return domain.Customer(
      id: row.id,
      displayName: row.displayName,
      status: domain.CustomerStatus.values.byName(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      mergedIntoId: row.mergedIntoId,
    );
  }

  domain.CustomerIdentifier _toIdentifier(CustomerIdentifier row) {
    return domain.CustomerIdentifier(
      id: row.id,
      customerId: row.customerId,
      type: domain.CustomerIdentifierType.values.byName(row.type),
      value: row.value,
      isPrimary: row.isPrimary,
    );
  }
}

final class LocalWalletRepository implements WalletRepository {
  const LocalWalletRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.Wallet?>> findById(String id) async {
    try {
      final row = await (database.select(database.wallets)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toWallet(row));
    } catch (error) {
      return Failure(_failure('wallet_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Wallet>>> listAll() async {
    try {
      final rows = await (database.select(database.wallets)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toWallet).toList(growable: false));
    } catch (error) {
      return Failure(_failure('wallet_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.Wallet wallet) async {
    try {
      await database.into(database.wallets).insertOnConflictUpdate(
            WalletsCompanion.insert(
              id: wallet.id,
              name: wallet.name,
              status: wallet.status.name,
              createdAt: wallet.createdAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('wallet_save_failed', error));
    }
  }

  domain.Wallet _toWallet(Wallet row) {
    return domain.Wallet(
      id: row.id,
      name: row.name,
      status: domain.WalletStatus.values.byName(row.status),
      createdAt: row.createdAt,
    );
  }
}

final class LocalPointOfSaleRepository implements PointOfSaleRepository {
  const LocalPointOfSaleRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.PointOfSale?>> findById(String id) async {
    try {
      final row = await (database.select(database.pointOfSales)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toPointOfSale(row));
    } catch (error) {
      return Failure(_failure('pos_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.PointOfSale>>> listAll() async {
    try {
      final rows = await (database.select(database.pointOfSales)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toPointOfSale).toList(growable: false));
    } catch (error) {
      return Failure(_failure('pos_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.PointOfSale pointOfSale) async {
    try {
      await database.into(database.pointOfSales).insertOnConflictUpdate(
            PointOfSalesCompanion.insert(
              id: pointOfSale.id,
              name: pointOfSale.name,
              status: pointOfSale.status.name,
              createdAt: pointOfSale.createdAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('pos_save_failed', error));
    }
  }

  domain.PointOfSale _toPointOfSale(PointOfSale row) {
    return domain.PointOfSale(
      id: row.id,
      name: row.name,
      status: domain.PointOfSaleStatus.values.byName(row.status),
      createdAt: row.createdAt,
    );
  }
}

final class LocalCardCategoryRepository implements CardCategoryRepository {
  const LocalCardCategoryRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.CardCategory?>> findById(String id) async {
    try {
      final row = await (database.select(database.cardCategories)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toCategory(row));
    } catch (error) {
      return Failure(_failure('category_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.CardCategory>>> listAll() async {
    try {
      final rows = await (database.select(database.cardCategories)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toCategory).toList(growable: false));
    } catch (error) {
      return Failure(_failure('category_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.CardCategory category) async {
    try {
      await database.into(database.cardCategories).insertOnConflictUpdate(
            CardCategoriesCompanion.insert(
              id: category.id,
              name: category.name,
              faceValueMinorUnits: category.faceValue.minorUnits,
              currencyCode: category.faceValue.currencyCode,
              isActive: Value(category.isActive),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('category_save_failed', error));
    }
  }

  domain.CardCategory _toCategory(CardCategory row) {
    return domain.CardCategory(
      id: row.id,
      name: row.name,
      faceValue: Money(
        minorUnits: row.faceValueMinorUnits,
        currencyCode: row.currencyCode,
      ),
      isActive: row.isActive,
    );
  }
}

final class LocalCardRepository implements CardRepository {
  const LocalCardRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.Card?>> findById(String id) async {
    try {
      final row = await (database.select(database.cards)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toCard(row));
    } catch (error) {
      return Failure(_failure('card_find_failed', error));
    }
  }

  @override
  Future<Result<domain.Card?>> findBySerialNumber(String serialNumber) async {
    try {
      final row = await (database.select(database.cards)
            ..where((table) => table.serialNumber.equals(serialNumber)))
          .getSingleOrNull();
      return Success(row == null ? null : _toCard(row));
    } catch (error) {
      return Failure(_failure('card_serial_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Card>>> findByCategory(String categoryId) async {
    try {
      final rows = await (database.select(database.cards)
            ..where((table) => table.categoryId.equals(categoryId))
            ..orderBy([(table) => OrderingTerm(expression: table.serialNumber)]))
          .get();
      return Success(rows.map(_toCard).toList(growable: false));
    } catch (error) {
      return Failure(_failure('card_category_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Card>>> findAvailableByCategory(String categoryId) async {
    try {
      final rows = await (database.select(database.cards)
            ..where(
              (table) =>
                  table.categoryId.equals(categoryId) &
                  table.status.equals(domain.CardStatus.available.name),
            )
            ..orderBy([(table) => OrderingTerm(expression: table.serialNumber)]))
          .get();
      return Success(rows.map(_toCard).toList(growable: false));
    } catch (error) {
      return Failure(_failure('card_available_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.Card card) async {
    try {
      await database.into(database.cards).insertOnConflictUpdate(
            CardsCompanion.insert(
              id: card.id,
              categoryId: card.categoryId,
              serialNumber: card.serialNumber,
              secretCode: card.secretCode,
              status: card.status.name,
              reservationId: Value(card.reservation.reservationId),
              reservedAt: Value(card.reservation.reservedAt),
              reservationExpiresAt: Value(card.reservation.expiresAt),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_save_failed', error));
    }
  }

  
  @override
  Future<Result<List<domain.Card>>> listByStatus(domain.CardStatus status) async {
    try {
      final rows = await (database.select(database.cards)
            ..where((table) => table.status.equals(status.name)))
          .get();
      return Success(rows.map(_toCard).toList(growable: false));
    } catch (error) {
      return Failure(_failure('card_list_by_status_failed', error));
    }
  }

@override
  Future<Result<int>> expireReservations(DateTime now) async {
    try {
      final changed = await (database.update(database.cards)
            ..where(
              (table) =>
                  table.status.equals(domain.CardStatus.reserved.name) &
                  table.reservationExpiresAt.isNotNull() &
                  table.reservationExpiresAt.isSmallerOrEqualValue(now),
            ))
          .write(
        const CardsCompanion(
          status: Value('available'),
          reservationId: Value(null),
          reservedAt: Value(null),
          reservationExpiresAt: Value(null),
        ),
      );
      return Success(changed);
    } catch (error) {
      return Failure(_failure('card_expire_failed', error));
    }
  }

  @override
  Future<Result<void>> reserve(
    String cardId,
    domain.CardReservation reservation,
  ) async {
    try {
      final changed = await (database.update(database.cards)
            ..where(
              (table) =>
                  table.id.equals(cardId) &
                  table.status.equals(domain.CardStatus.available.name),
            ))
          .write(
        CardsCompanion(
          status: const Value('reserved'),
          reservationId: Value(reservation.reservationId),
          reservedAt: Value(reservation.reservedAt),
          reservationExpiresAt: Value(reservation.expiresAt),
        ),
      );
      if (changed != 1) {
        return const Failure(
          AppFailure(code: 'card_not_available', message: 'Card is not available'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_reserve_failed', error));
    }
  }

  @override
  Future<Result<void>> releaseReservation(String cardId, String reservationId) async {
    try {
      final changed = await (database.update(database.cards)
            ..where(
              (table) =>
                  table.id.equals(cardId) &
                  table.reservationId.equals(reservationId),
            ))
          .write(
        const CardsCompanion(
          status: Value('available'),
          reservationId: Value(null),
          reservedAt: Value(null),
          reservationExpiresAt: Value(null),
        ),
      );
      if (changed != 1) {
        return const Failure(
          AppFailure(code: 'reservation_not_found', message: 'Reservation was not found'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_release_failed', error));
    }
  }

  @override
  Future<Result<void>> markSold(String cardId, String saleId) async {
    try {
      final changed = await (database.update(database.cards)
            ..where(
              (table) =>
                  table.id.equals(cardId) &
                  table.status.equals(domain.CardStatus.reserved.name),
            ))
          .write(
        const CardsCompanion(
          status: Value('sold'),
          reservationId: Value(null),
          reservedAt: Value(null),
          reservationExpiresAt: Value(null),
        ),
      );
      if (changed != 1) {
        return const Failure(
          AppFailure(
            code: 'card_not_reserved',
            message: 'Card must be reserved before it can be sold',
          ),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_mark_sold_failed', error));
    }
  }

  @override
  Future<Result<void>> restoreAvailable(String cardId) async {
    try {
      final changed = await (database.update(database.cards)
            ..where(
              (table) =>
                  table.id.equals(cardId) &
                  table.status.equals(domain.CardStatus.sold.name),
            ))
          .write(
        const CardsCompanion(
          status: Value('available'),
          reservationId: Value(null),
          reservedAt: Value(null),
          reservationExpiresAt: Value(null),
        ),
      );
      if (changed != 1) {
        return const Failure(
          AppFailure(code: 'card_not_sold', message: 'Card is not sold'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_restore_failed', error));
    }
  }

  domain.Card _toCard(Card row) {
    final reservation = row.reservationId == null
        ? const domain.CardReservation.none()
        : domain.CardReservation(
            reservationId: row.reservationId,
            reservedAt: row.reservedAt,
            expiresAt: row.reservationExpiresAt,
          );
    return domain.Card(
      id: row.id,
      categoryId: row.categoryId,
      serialNumber: row.serialNumber,
      secretCode: row.secretCode,
      status: domain.CardStatus.values.byName(row.status),
      reservation: reservation,
    );
  }
}

final class LocalTransactionRepository implements TransactionRepository {
  const LocalTransactionRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<void>> append(domain.Transaction transaction) async {
    try {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: transaction.id,
              type: transaction.type.name,
              status: transaction.status.name,
              amountMinorUnits: transaction.amount.minorUnits,
              currencyCode: transaction.amount.currencyCode,
              createdAt: transaction.createdAt,
              customerId: Value(transaction.customerId),
              reference: Value(transaction.reference),
              relatedTransactionId: Value(transaction.relatedTransactionId),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('transaction_append_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Transaction>>> findByCustomer(String customerId) async {
    try {
      final rows = await (database.select(database.transactions)
            ..where((table) => table.customerId.equals(customerId))
            ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
          .get();
      return Success(rows.map(_toTransaction).toList(growable: false));
    } catch (error) {
      return Failure(_failure('transaction_customer_find_failed', error));
    }
  }

  @override
  Future<Result<domain.Transaction?>> findByReference(String reference) async {
    try {
      final row = await (database.select(database.transactions)
            ..where((table) => table.reference.equals(reference)))
          .getSingleOrNull();
      return Success(row == null ? null : _toTransaction(row));
    } catch (error) {
      return Failure(_failure('transaction_reference_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Transaction>>> listRecent({int limit = 50}) async {
    try {
      final rows = await (database.select(database.transactions)
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(limit))
          .get();
      return Success(rows.map(_toTransaction).toList(growable: false));
    } catch (error) {
      return Failure(_failure('transaction_list_recent_failed', error));
    }
  }

  domain.Transaction _toTransaction(Transaction row) {
    return domain.Transaction(
      id: row.id,
      type: domain.TransactionType.values.byName(row.type),
      status: domain.TransactionStatus.values.byName(row.status),
      amount: Money(
        minorUnits: row.amountMinorUnits,
        currencyCode: row.currencyCode,
      ),
      createdAt: row.createdAt,
      customerId: row.customerId,
      reference: row.reference,
      relatedTransactionId: row.relatedTransactionId,
    );
  }
}

final class LocalSaleRepository implements SaleRepository {
  const LocalSaleRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<void>> save(domain.Sale sale) async {
    try {
      await database.into(database.sales).insertOnConflictUpdate(
            SalesCompanion.insert(
              id: sale.id,
              customerId: sale.customerId,
              cardId: sale.cardId,
              amountMinorUnits: sale.amount.minorUnits,
              currencyCode: sale.amount.currencyCode,
              status: sale.status.name,
              createdAt: sale.createdAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('sale_save_failed', error));
    }
  }

  @override
  Future<Result<domain.Sale?>> findById(String id) async {
    try {
      final row = await (database.select(database.sales)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toSale(row));
    } catch (error) {
      return Failure(_failure('sale_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Sale>>> findByCustomer(String customerId) async {
    try {
      final rows = await (database.select(database.sales)
            ..where((table) => table.customerId.equals(customerId))
            ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
          .get();
      return Success(rows.map(_toSale).toList(growable: false));
    } catch (error) {
      return Failure(_failure('sale_customer_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Sale>>> listRecent({int limit = 50}) async {
    try {
      final rows = await (database.select(database.sales)
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(limit))
          .get();
      return Success(rows.map(_toSale).toList(growable: false));
    } catch (error) {
      return Failure(_failure('sale_list_recent_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Sale>>> listCompletedBetween(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final rows = await (database.select(database.sales)
            ..where(
              (table) =>
                  table.createdAt.isBiggerOrEqualValue(from) &
                  table.createdAt.isSmallerOrEqualValue(to),
            )
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .get();
      final mapped = rows
          .map(_toSale)
          .where((s) => s.status == domain.TransactionStatus.completed)
          .toList(growable: false);
      return Success(mapped);
    } catch (error) {
      return Failure(_failure('sale_list_between_failed', error));
    }
  }

  domain.Sale _toSale(Sale row) {
    return domain.Sale(
      id: row.id,
      customerId: row.customerId,
      cardId: row.cardId,
      amount: Money(
        minorUnits: row.amountMinorUnits,
        currencyCode: row.currencyCode,
      ),
      status: domain.TransactionStatus.values.byName(row.status),
      createdAt: row.createdAt,
    );
  }
}

final class LocalMessageRepository implements MessageRepository {
  const LocalMessageRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<void>> save(domain.IncomingMessage message) async {
    try {
      await database.into(database.incomingMessages).insertOnConflictUpdate(
            IncomingMessagesCompanion.insert(
              id: message.id,
              sender: message.sender,
              body: message.body,
              receivedAt: message.receivedAt,
              status: message.status.name,
              externalReference: Value(message.externalReference),
              customerIdentifier: Value(message.customerIdentifier),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('message_save_failed', error));
    }
  }

  @override
  Future<Result<domain.IncomingMessage?>> findById(String id) async {
    try {
      final row = await (database.select(database.incomingMessages)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toMessage(row));
    } catch (error) {
      return Failure(_failure('message_find_failed', error));
    }
  }

  @override
  Future<Result<domain.IncomingMessage?>> findByExternalReference(
    String reference,
  ) async {
    try {
      final row = await (database.select(database.incomingMessages)
            ..where((table) => table.externalReference.equals(reference)))
          .getSingleOrNull();
      return Success(row == null ? null : _toMessage(row));
    } catch (error) {
      return Failure(_failure('message_reference_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.IncomingMessage>>> pendingProcessing() async {
    try {
      final rows = await (database.select(database.incomingMessages)
            ..where(
              (table) => table.status.equals(
                domain.MessageProcessingStatus.received.name,
              ),
            )
            ..orderBy([(table) => OrderingTerm(expression: table.receivedAt)]))
          .get();
      return Success(rows.map(_toMessage).toList(growable: false));
    } catch (error) {
      return Failure(_failure('message_pending_find_failed', error));
    }
  }

  
  @override
  Future<Result<List<domain.IncomingMessage>>> listByStatus(
    domain.MessageProcessingStatus status,
  ) async {
    try {
      final rows = await (database.select(database.incomingMessages)
            ..where((table) => table.status.equals(status.name))
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.receivedAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .get();
      return Success(rows.map(_toMessage).toList(growable: false));
    } catch (error) {
      return Failure(_failure('message_list_by_status_failed', error));
    }
  }

  @override
  Future<Result<List<domain.IncomingMessage>>> listRecent({int limit = 100}) async {
    try {
      final rows = await (database.select(database.incomingMessages)
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.receivedAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(limit))
          .get();
      return Success(rows.map(_toMessage).toList(growable: false));
    } catch (error) {
      return Failure(_failure('message_list_recent_failed', error));
    }
  }

@override
  Future<Result<void>> updateStatus(
    String id,
    domain.MessageProcessingStatus status,
  ) async {
    try {
      final changed = await (database.update(database.incomingMessages)
            ..where((table) => table.id.equals(id)))
          .write(IncomingMessagesCompanion(status: Value(status.name)));
      if (changed != 1) {
        return const Failure(
          AppFailure(code: 'message_not_found', message: 'Message was not found'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('message_status_update_failed', error));
    }
  }

  domain.IncomingMessage _toMessage(IncomingMessage row) {
    return domain.IncomingMessage(
      id: row.id,
      sender: row.sender,
      body: row.body,
      receivedAt: row.receivedAt,
      status: domain.MessageProcessingStatus.values.byName(row.status),
      externalReference: row.externalReference,
      customerIdentifier: row.customerIdentifier,
    );
  }
}

final class LocalLicenseRepository implements LicenseRepository {
  const LocalLicenseRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.License?>> getCurrent() async {
    try {
      final rows = await database.select(database.licenses).get();
      if (rows.isEmpty) return const Success(null);
      return Success(_toLicense(rows.first));
    } catch (error) {
      return Failure(_failure('license_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.License license) async {
    try {
      await database.into(database.licenses).insertOnConflictUpdate(
            LicensesCompanion.insert(
              id: license.id,
              status: license.status.name,
              expiresAt: Value(license.expiresAt),
              deviceBinding: Value(license.deviceBinding),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('license_save_failed', error));
    }
  }

  domain.License _toLicense(License row) {
    return domain.License(
      id: row.id,
      status: domain.LicenseStatus.values.byName(row.status),
      expiresAt: row.expiresAt,
      deviceBinding: row.deviceBinding,
    );
  }
}

final class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.AppSetting?>> find(String key) async {
    try {
      final row = await (database.select(database.appSettings)
            ..where((table) => table.key.equals(key)))
          .getSingleOrNull();
      return Success(row == null ? null : _toSetting(row));
    } catch (error) {
      return Failure(_failure('setting_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.AppSetting setting) async {
    try {
      await database.into(database.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: setting.key,
              value: setting.value,
              updatedAt: setting.updatedAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('setting_save_failed', error));
    }
  }

  domain.AppSetting _toSetting(AppSetting row) {
    return domain.AppSetting(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }
}

final class LocalAuditLogRepository implements AuditLogRepository {
  const LocalAuditLogRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<void>> append(domain.AuditLog log) async {
    try {
      await database.into(database.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: log.id,
              entityType: log.entityType,
              entityId: log.entityId,
              action: log.action,
              payloadJson: Value(log.payloadJson),
              occurredAt: log.occurredAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('audit_append_failed', error));
    }
  }

  @override
  Future<Result<List<domain.AuditLog>>> findByEntity(
    String entityType,
    String entityId,
  ) async {
    try {
      final rows = await (database.select(database.auditLogs)
            ..where(
              (table) =>
                  table.entityType.equals(entityType) &
                  table.entityId.equals(entityId),
            )
            ..orderBy([(table) => OrderingTerm(expression: table.occurredAt)]))
          .get();
      return Success(rows.map(_toAudit).toList(growable: false));
    } catch (error) {
      return Failure(_failure('audit_find_failed', error));
    }
  }

  domain.AuditLog _toAudit(AuditLog row) {
    return domain.AuditLog(
      id: row.id,
      entityType: row.entityType,
      entityId: row.entityId,
      action: row.action,
      payloadJson: row.payloadJson,
      occurredAt: row.occurredAt,
    );
  }
}

AppFailure _failure(String code, Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('unique constraint failed')) {
    if (lower.contains('customer_identifiers')) {
      return const AppFailure(
        code: 'duplicate_identifier',
        message: 'Identifier already exists',
      );
    }
    if (lower.contains('serial_number')) {
      return const AppFailure(
        code: 'duplicate_serial',
        message: 'Card serial already exists',
      );
    }
    if (lower.contains('secret_code')) {
      return const AppFailure(
        code: 'duplicate_secret',
        message: 'Card secret already exists',
      );
    }
    if (lower.contains('incoming_messages')) {
      return const AppFailure(
        code: 'duplicate_message_reference',
        message: 'Message reference already exists',
      );
    }
    if (lower.contains('transactions') || lower.contains('reference')) {
      return const AppFailure(
        code: 'duplicate_reference',
        message: 'Reference already exists',
      );
    }
    return AppFailure(code: 'unique_constraint', message: text);
  }
  return AppFailure(code: code, message: text);
}


final class LocalTransferTemplateRepository implements TransferTemplateRepository {
  const LocalTransferTemplateRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<List<domain.TransferTemplate>>> listAll() async {
    try {
      final rows = await (database.select(database.transferTemplates)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toTemplate).toList(growable: false));
    } catch (error) {
      return Failure(_failure('template_list_failed', error));
    }
  }

  @override
  Future<Result<domain.TransferTemplate?>> findById(String id) async {
    try {
      final row = await (database.select(database.transferTemplates)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toTemplate(row));
    } catch (error) {
      return Failure(_failure('template_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.TransferTemplate template) async {
    try {
      await database.into(database.transferTemplates).insertOnConflictUpdate(
            TransferTemplatesCompanion.insert(
              id: template.id,
              name: template.name,
              pattern: template.pattern,
              isActive: Value(template.isActive),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('template_save_failed', error));
    }
  }

  domain.TransferTemplate _toTemplate(TransferTemplate row) {
    return domain.TransferTemplate(
      id: row.id,
      name: row.name,
      pattern: row.pattern,
      isActive: row.isActive,
    );
  }
}
