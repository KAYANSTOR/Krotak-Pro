part of local_repositories;

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
