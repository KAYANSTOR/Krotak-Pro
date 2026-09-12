part of local_repositories;

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
