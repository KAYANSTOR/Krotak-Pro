part of local_repositories;

final class LocalMessageRepository implements MessageRepository, OutboundMessageStore {
  const LocalMessageRepository(this.database);

  final AppDatabase database;

  @override
  Future<bool> claimForDispatch(
    String messageId, {
    required DateTime now,
    required DateTime staleBefore,
  }) async {
    final changed = await database.customUpdate(
      'UPDATE incoming_messages SET status = ?, last_attempt_at = ? '
      'WHERE id = ? AND status IN (?, ?, ?) '
      'AND (last_attempt_at IS NULL OR last_attempt_at < ?)',
      variables: [
        Variable.withString(domain.MessageProcessingStatus.sending.name),
        Variable.withDateTime(now),
        Variable.withString(messageId),
        Variable.withString(domain.MessageProcessingStatus.pending.name),
        Variable.withString(domain.MessageProcessingStatus.failed.name),
        Variable.withString(domain.MessageProcessingStatus.sending.name),
        Variable.withDateTime(staleBefore),
      ],
      updates: {database.incomingMessages},
    );
    return changed == 1;
  }

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
  /// Includes pending/sending for Phase 4 delivery worker + failed for retry.
  /// Terminal [rejected] and [processed] rows are never replayed automatically.
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
                    domain.MessageProcessingStatus.pending.name,
                  ) |
                  table.status.equals(
                    domain.MessageProcessingStatus.sending.name,
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
  Future<Result<int>> countByStatus(domain.MessageProcessingStatus status) async {
    try {
      final query = database.selectOnly(database.incomingMessages)
        ..where(database.incomingMessages.status.equals(status.name))
        ..addColumns([database.incomingMessages.id.count()]);
      final row = await query.getSingle();
      final value = row.read(database.incomingMessages.id.count()) ?? 0;
      return Success(value);
    } catch (error) {
      return Failure(_failure('message_count_by_status_failed', error));
    }
  }

  @override
  Stream<int> watchCountByStatus(domain.MessageProcessingStatus status) {
    final countExp = database.incomingMessages.id.count();
    final query = database.selectOnly(database.incomingMessages)
      ..where(database.incomingMessages.status.equals(status.name))
      ..addColumns([countExp]);
    return query.watch().map((rows) {
      if (rows.isEmpty) return 0;
      return rows.first.read(countExp) ?? 0;
    });
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

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final changed = await (database.delete(database.incomingMessages)
            ..where((table) => table.id.equals(id)))
          .go();
      if (changed != 1) {
        return const Failure(
          AppFailure(code: 'message_not_found', message: 'Message was not found'),
        );
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('message_delete_failed', error));
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
