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
      final keys = PhoneNormalizer.lookupKeys(value);
      if (keys.isEmpty) return const Success(null);

      final identifierQuery = database.select(database.customerIdentifiers)
        ..where((table) => table.value.isIn(keys));
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
    return searchPage(query, limit: 100000, offset: 0);
  }

  @override
  Future<Result<List<domain.Customer>>> searchPage(
    String query, {
    int limit = 80,
    int offset = 0,
  }) async {
    try {
      final safeLimit = limit < 1 ? 80 : limit;
      final safeOffset = offset < 0 ? 0 : offset;
      final trimmed = query.trim();

      if (trimmed.isEmpty) {
        final rows = await (database.select(database.customers)
              ..orderBy([(table) => OrderingTerm(expression: table.displayName)])
              ..limit(safeLimit, offset: safeOffset))
            .get();
        return Success(rows.map(_toCustomer).toList(growable: false));
      }

      final byName = await (database.select(database.customers)
            ..where((table) => table.displayName.contains(trimmed)))
          .get();
      final phoneKeys = PhoneNormalizer.lookupKeys(trimmed);
      final identifiers = await (database.select(database.customerIdentifiers)
            ..where((table) =>
                table.value.contains(trimmed) | table.value.isIn(phoneKeys)))
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
      final window = rows.skip(safeOffset).take(safeLimit);
      return Success(window.map(_toCustomer).toList(growable: false));
    } catch (error) {
      return Failure(_failure('customer_search_page_failed', error));
    }
  }

  @override
  Future<Result<List<domain.CustomerPhoneSuggestion>>> suggestPhonesByPrefix(
    String prefix, {
    int limit = 8,
  }) async {
    try {
      final raw = prefix.trim();
      if (raw.isEmpty || limit <= 0) {
        return const Success(<domain.CustomerPhoneSuggestion>[]);
      }

      final digits = PhoneNormalizer.digitsOnly(raw);
      if (digits.isEmpty) {
        return const Success(<domain.CustomerPhoneSuggestion>[]);
      }

      final prefixes = <String>{
        digits,
        if (!digits.startsWith('0')) '0$digits',
        if (!digits.startsWith('967')) '967$digits',
      };

      final orExpr = prefixes
          .map((pref) => database.customerIdentifiers.value.like('$pref%'))
          .reduce((a, b) => a | b);

      final idRows = await (database.select(database.customerIdentifiers)
            ..where(
              (t) =>
                  t.type.equals(domain.CustomerIdentifierType.phoneNumber.name) &
                  orExpr,
            )
            ..limit(limit * 4))
          .get();

      if (idRows.isEmpty) {
        return const Success(<domain.CustomerPhoneSuggestion>[]);
      }

      final customerIds = idRows.map((r) => r.customerId).toSet().toList();
      final customers = await (database.select(database.customers)
            ..where((t) => t.id.isIn(customerIds)))
          .get();
      final byId = {for (final c in customers) c.id: c};

      const blocked = {'blacklisted', 'merged', 'archived'};

      final suggestions = <domain.CustomerPhoneSuggestion>[];
      final seenPhones = <String>{};

      idRows.sort((a, b) {
        final ca = byId[a.customerId];
        final cb = byId[b.customerId];
        final ta = ca?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = cb?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = tb.compareTo(ta);
        if (cmp != 0) return cmp;
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.value.compareTo(b.value);
      });

      for (final row in idRows) {
        final cust = byId[row.customerId];
        if (cust == null) continue;
        if (blocked.contains(cust.status)) continue;

        final phone = PhoneNormalizer.canonicalize(row.value) ?? row.value;
        if (phone.isEmpty || seenPhones.contains(phone)) continue;

        final phoneDigits = PhoneNormalizer.digitsOnly(phone);
        final matchesPrefix = phoneDigits.startsWith(digits) ||
            row.value.startsWith(raw) ||
            row.value.startsWith(digits);
        if (!matchesPrefix) continue;

        seenPhones.add(phone);
        suggestions.add(
          domain.CustomerPhoneSuggestion(
            customerId: cust.id,
            phone: phone,
            displayName: cust.displayName,
            status: domain.CustomerStatus.values.byName(cust.status),
            updatedAt: cust.updatedAt,
          ),
        );
        if (suggestions.length >= limit) break;
      }

      return Success(suggestions);
    } catch (error) {
      return Failure(_failure('customer_suggest_phones_failed', error));
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
