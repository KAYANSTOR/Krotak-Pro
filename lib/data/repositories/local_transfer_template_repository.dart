part of local_repositories;

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
