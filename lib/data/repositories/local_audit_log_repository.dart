part of local_repositories;

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
  Future<Result<List<domain.AuditLog>>> search({
    required String query,
    int limit = 200,
  }) async {
    final needle = query.trim();
    if (needle.isEmpty) {
      return const Success([]);
    }
    try {
      final like = '%$needle%';
      final rows = await (database.select(database.auditLogs)
            ..where(
              (table) =>
                  table.entityId.like(like) |
                  table.action.like(like) |
                  table.payloadJson.like(like),
            )
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.occurredAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .get();
      return Success(rows.map(_toAudit).toList(growable: false));
    } catch (error) {
      return Failure(_failure('audit_search_failed', error));
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
