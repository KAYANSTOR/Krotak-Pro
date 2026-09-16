part of local_repositories;

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
  Future<Result<Set<String>>> existingSerialsAmong(Iterable<String> serials) async {
    try {
      final needles = serials.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      if (needles.isEmpty) return const Success(<String>{});
      final rows = await database.select(database.cards).get();
      final hit = <String>{};
      for (final row in rows) {
        if (needles.contains(row.serialNumber)) hit.add(row.serialNumber);
      }
      return Success(hit);
    } catch (error) {
      return Failure(_failure('card_existing_serials_failed', error));
    }
  }

  @override
  Future<Result<Set<String>>> existingSecretsAmong(Iterable<String> secrets) async {
    try {
      final needles = secrets.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      if (needles.isEmpty) return const Success(<String>{});
      final rows = await database.select(database.cards).get();
      final hit = <String>{};
      for (final row in rows) {
        if (needles.contains(row.secretCode)) hit.add(row.secretCode);
      }
      return Success(hit);
    } catch (error) {
      return Failure(_failure('card_existing_secrets_failed', error));
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
  Future<Result<void>> saveAll(List<domain.Card> cards) async {
    for (final card in cards) {
      final r = await save(card);
      if (r is Failure<void>) return r;
    }
    return const Success(null);
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
