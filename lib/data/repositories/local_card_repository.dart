part of local_repositories;

final class LocalCardRepository implements CardRepository {
  const LocalCardRepository(this.database);

  final AppDatabase database;

  static const _lookupChunk = 400;
  static const _insertChunk = 200;

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
            _companion(card),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_save_failed', error));
    }
  }

  @override
  Future<Result<int>> saveAll(List<domain.Card> cards) async {
    if (cards.isEmpty) return const Success(0);
    try {
      var written = 0;
      for (var i = 0; i < cards.length; i += _insertChunk) {
        final end = i + _insertChunk > cards.length ? cards.length : i + _insertChunk;
        final slice = cards.sublist(i, end);
        await database.batch((batch) {
          batch.insertAll(database.cards, slice.map(_companion).toList(growable: false));
        });
        written += slice.length;
      }
      return Success(written);
    } catch (error) {
      return Failure(_failure('card_save_all_failed', error));
    }
  }

  @override
  Future<Result<Set<String>>> findExistingSerials(List<String> serialNumbers) async {
    if (serialNumbers.isEmpty) return const Success(<String>{});
    try {
      final found = <String>{};
      for (var i = 0; i < serialNumbers.length; i += _lookupChunk) {
        final end = i + _lookupChunk > serialNumbers.length
            ? serialNumbers.length
            : i + _lookupChunk;
        final slice = serialNumbers.sublist(i, end);
        final rows = await (database.select(database.cards)
              ..where((table) => table.serialNumber.isIn(slice)))
            .get();
        found.addAll(rows.map((row) => row.serialNumber));
      }
      return Success(found);
    } catch (error) {
      return Failure(_failure('card_serial_lookup_failed', error));
    }
  }

  @override
  Future<Result<Set<String>>> findExistingSecrets(List<String> secretCodes) async {
    if (secretCodes.isEmpty) return const Success(<String>{});
    try {
      final found = <String>{};
      for (var i = 0; i < secretCodes.length; i += _lookupChunk) {
        final end = i + _lookupChunk > secretCodes.length ? secretCodes.length : i + _lookupChunk;
        final slice = secretCodes.sublist(i, end);
        final rows = await (database.select(database.cards)
              ..where((table) => table.secretCode.isIn(slice)))
            .get();
        found.addAll(rows.map((row) => row.secretCode));
      }
      return Success(found);
    } catch (error) {
      return Failure(_failure('card_secret_lookup_failed', error));
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

  CardsCompanion _companion(domain.Card card) {
    return CardsCompanion.insert(
      id: card.id,
      categoryId: card.categoryId,
      serialNumber: card.serialNumber,
      secretCode: card.secretCode,
      status: card.status.name,
      reservationId: Value(card.reservation.reservationId),
      reservedAt: Value(card.reservation.reservedAt),
      reservationExpiresAt: Value(card.reservation.expiresAt),
    );
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
