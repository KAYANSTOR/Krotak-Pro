part of local_repositories;

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
