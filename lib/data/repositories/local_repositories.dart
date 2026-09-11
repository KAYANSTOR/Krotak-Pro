import 'package:drift/drift.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart' as domain;
import '../../domain/entities/message.dart' as domain;
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
      final rows = await (database.select(database.customers)
            ..where((table) => table.displayName.contains(query))
            ..orderBy([(table) => OrderingTerm(expression: table.displayName)]))
          .get();
      return Success(rows.map(_toCustomer).toList(growable: false));
    } catch (error) {
      return Failure(_failure('customer_search_failed', error));
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
              mergedIntoId: const Value(null),
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
      await database.into(database.customerIdentifiers).insertOnConflictUpdate(
            CustomerIdentifiersCompanion.insert(
              id: identifier.id,
              customerId: identifier.customerId,
              type: identifier.type.name,
              value: identifier.value,
              isPrimary: Value(identifier.isPrimary),
            ),
          );
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
  Future<Result<List<domain.Card>>> findAvailableByCategory(String categoryId) async {
    try {
      final rows = await (database.select(database.cards)
            ..where(
              (table) =>
                  table.categoryId.equals(categoryId) &
                  table.status.equals(domain.CardStatus.available.name),
            ))
          .get();
      return Success(rows.map(_toCard).toList(growable: false));
    } catch (error) {
      return Failure(_failure('card_available_find_failed', error));
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
            ..where((table) => table.id.equals(cardId)))
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
          AppFailure(code: 'card_not_found', message: 'Card was not found'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_mark_sold_failed', error));
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

AppFailure _failure(String code, Object error) {
  return AppFailure(code: code, message: error.toString());
}
