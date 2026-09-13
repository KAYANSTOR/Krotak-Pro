part of local_repositories;

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

  /// Messages eligible for recovery / deferred commercial processing.
  /// Failed rows are included for Phase 4 retry orchestration; terminal
  /// [rejected] and [processed] rows are never replayed automatically.
  @override
  Future<Result<List<domain.IncomingMessage>>> pendingProcessing() async {
    try {
      final rows = await (database.select(database.incomingMessages)
            ..where(
              (table) =>
                  table.status.equals(
                    domain.MessageProcessingStatus.received.name,
                  ) |
                  table.status.equals(
                    domain.MessageProcessingStatus.parsed.name,
                  ) |
                  table.status.equals(
                    domain.MessageProcessingStatus.failed.name,
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
