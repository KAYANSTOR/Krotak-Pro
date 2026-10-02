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
  Future<Result<List<domain.Customer>>> searchFilteredPage(
    String query, {
    required domain.AccountSqlFilter filter,
    domain.AccountSqlSort sort = domain.AccountSqlSort.name,
    String currencyCode = 'YER',
    int limit = 80,
    int offset = 0,
  }) async {
    try {
      final safeLimit = limit < 1 ? 1 : limit;
      final safeOffset = offset < 0 ? 0 : offset;
      final trimmed = query.trim();
      final like = '%$trimmed%';
      final rows = await database.customSelect(
        '''
        SELECT c.id AS id
        FROM customers c
        LEFT JOIN (
          SELECT customer_id,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND currency_code = ?
            AND customer_id IS NOT NULL
          GROUP BY customer_id
        ) bal ON bal.customer_id = c.id
        WHERE c.status != 'merged'
          AND (
            ? = 'all'
            OR (? = 'debtor' AND COALESCE(bal.signed_balance, 0) < 0)
            OR (? = 'creditor' AND COALESCE(bal.signed_balance, 0) > 0)
            OR (? = 'zero' AND COALESCE(bal.signed_balance, 0) = 0)
            OR (? = 'provisional' AND c.status = 'provisional')
            OR (? = 'unlinked' AND NOT EXISTS (
              SELECT 1 FROM customer_identifiers i
              WHERE i.customer_id = c.id
                AND i.type = 'phoneNumber'
                AND TRIM(i.value) != ''
            ))
          )
          AND (
            ? = ''
            OR c.display_name LIKE ?
            OR EXISTS (
              SELECT 1 FROM customer_identifiers i2
              WHERE i2.customer_id = c.id AND i2.value LIKE ?
            )
          )
        ORDER BY ${domain.accountSqlOrderBy(sort)}
        LIMIT ? OFFSET ?
        ''',
        variables: [
          Variable.withString(currencyCode),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(trimmed),
          Variable.withString(like),
          Variable.withString(like),
          Variable.withInt(safeLimit),
          Variable.withInt(safeOffset),
        ],
        readsFrom: {
          database.customers,
          database.transactions,
          database.customerIdentifiers,
        },
      ).get();
      if (rows.isEmpty) return const Success(<domain.Customer>[]);
      final ids = rows.map((row) => row.read<String>('id')).toList();
      final customers = await (database.select(database.customers)
            ..where((table) => table.id.isIn(ids)))
          .get();
      final byId = {for (final row in customers) row.id: _toCustomer(row)};
      return Success([
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ]);
    } catch (error) {
      return Failure(_failure('customer_filtered_page_failed', error));
    }
  }


  @override
  Future<Result<int>> countFiltered(
    String query, {
    required domain.AccountSqlFilter filter,
    String currencyCode = 'YER',
  }) async {
    try {
      final trimmed = query.trim();
      final like = '%$trimmed%';
      final row = await database.customSelect(
        '''
        SELECT COUNT(*) AS match_count
        FROM customers c
        LEFT JOIN (
          SELECT customer_id,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND currency_code = ?
            AND customer_id IS NOT NULL
          GROUP BY customer_id
        ) bal ON bal.customer_id = c.id
        WHERE c.status != 'merged'
          AND (
            ? = 'all'
            OR (? = 'debtor' AND COALESCE(bal.signed_balance, 0) < 0)
            OR (? = 'creditor' AND COALESCE(bal.signed_balance, 0) > 0)
            OR (? = 'zero' AND COALESCE(bal.signed_balance, 0) = 0)
            OR (? = 'provisional' AND c.status = 'provisional')
            OR (? = 'unlinked' AND NOT EXISTS (
              SELECT 1 FROM customer_identifiers i
              WHERE i.customer_id = c.id
                AND i.type = 'phoneNumber'
                AND TRIM(i.value) != ''
            ))
          )
          AND (
            ? = ''
            OR c.display_name LIKE ?
            OR EXISTS (
              SELECT 1 FROM customer_identifiers i2
              WHERE i2.customer_id = c.id AND i2.value LIKE ?
            )
          )
        ''',
        variables: [
          Variable.withString(currencyCode),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(filter.name),
          Variable.withString(trimmed),
          Variable.withString(like),
          Variable.withString(like),
        ],
        readsFrom: {
          database.customers,
          database.transactions,
          database.customerIdentifiers,
        },
      ).getSingle();
      return Success(row.read<int>('match_count'));
    } catch (error) {
      return Failure(_failure('customer_filtered_count_failed', error));
    }
  }

  @override
  Future<Result<domain.AccountFilterCounts>> countFilterBuckets(
    String query, {
    String currencyCode = 'YER',
  }) async {
    try {
      final trimmed = query.trim();
      final like = '%$trimmed%';
      final row = await database.customSelect(
        '''
        SELECT
          COUNT(*) AS all_count,
          SUM(CASE WHEN COALESCE(bal.signed_balance, 0) < 0 THEN 1 ELSE 0 END) AS debtor_count,
          SUM(CASE WHEN COALESCE(bal.signed_balance, 0) > 0 THEN 1 ELSE 0 END) AS creditor_count,
          SUM(CASE WHEN COALESCE(bal.signed_balance, 0) = 0 THEN 1 ELSE 0 END) AS zero_count,
          SUM(CASE WHEN c.status = 'provisional' THEN 1 ELSE 0 END) AS provisional_count,
          SUM(CASE WHEN NOT EXISTS (
            SELECT 1 FROM customer_identifiers i
            WHERE i.customer_id = c.id
              AND i.type = 'phoneNumber'
              AND TRIM(i.value) != ''
          ) THEN 1 ELSE 0 END) AS unlinked_count
        FROM customers c
        LEFT JOIN (
          SELECT customer_id,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND currency_code = ?
            AND customer_id IS NOT NULL
          GROUP BY customer_id
        ) bal ON bal.customer_id = c.id
        WHERE c.status != 'merged'
          AND (
            ? = ''
            OR c.display_name LIKE ?
            OR EXISTS (
              SELECT 1 FROM customer_identifiers i2
              WHERE i2.customer_id = c.id AND i2.value LIKE ?
            )
          )
        ''',
        variables: [
          Variable.withString(currencyCode),
          Variable.withString(trimmed),
          Variable.withString(like),
          Variable.withString(like),
        ],
        readsFrom: {
          database.customers,
          database.transactions,
          database.customerIdentifiers,
        },
      ).getSingle();
      int read(String name) => row.read<int?>(name) ?? 0;
      return Success(domain.AccountFilterCounts(
        all: read('all_count'),
        debtor: read('debtor_count'),
        creditor: read('creditor_count'),
        zero: read('zero_count'),
        provisional: read('provisional_count'),
        unlinked: read('unlinked_count'),
      ));
    } catch (error) {
      return Failure(_failure('customer_filter_buckets_failed', error));
    }
  }

  @override
  Future<Result<domain.AccountLedgerTotals>> sumLedgerSides(
    String query, {
    domain.AccountSqlFilter filter = domain.AccountSqlFilter.all,
    String currencyCode = 'YER',
  }) async {
    try {
      final trimmed = query.trim();
      final like = '%$trimmed%';
      final filterName = filter.name;
      final row = await database.customSelect(
        """
        SELECT
          COALESCE(SUM(CASE
            WHEN COALESCE(bal.signed_balance, 0) < 0 THEN -bal.signed_balance
            ELSE 0
          END), 0) AS debtor_minor,
          COALESCE(SUM(CASE
            WHEN COALESCE(bal.signed_balance, 0) > 0 THEN bal.signed_balance
            ELSE 0
          END), 0) AS creditor_minor
        FROM customers c
        LEFT JOIN (
          SELECT customer_id,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND currency_code = ?
            AND customer_id IS NOT NULL
          GROUP BY customer_id
        ) bal ON bal.customer_id = c.id
        WHERE c.status != 'merged'
          AND (
            ? = 'all'
            OR (? = 'debtor' AND COALESCE(bal.signed_balance, 0) < 0)
            OR (? = 'creditor' AND COALESCE(bal.signed_balance, 0) > 0)
            OR (? = 'zero' AND COALESCE(bal.signed_balance, 0) = 0)
            OR (? = 'provisional' AND c.status = 'provisional')
            OR (? = 'unlinked' AND NOT EXISTS (
              SELECT 1 FROM customer_identifiers i
              WHERE i.customer_id = c.id
                AND i.type = 'phoneNumber'
                AND TRIM(i.value) != ''
            ))
          )
          AND (
            ? = ''
            OR c.display_name LIKE ?
            OR EXISTS (
              SELECT 1 FROM customer_identifiers i2
              WHERE i2.customer_id = c.id AND i2.value LIKE ?
            )
          )
        """,
        variables: [
          Variable.withString(currencyCode),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(trimmed),
          Variable.withString(like),
          Variable.withString(like),
        ],
        readsFrom: {
          database.customers,
          database.transactions,
          database.customerIdentifiers,
        },
      ).getSingle();
      int readSum(String name) {
        final value = row.data[name];
        if (value is int) return value;
        if (value is BigInt) return value.toInt();
        if (value is num) return value.toInt();
        return 0;
      }
      return Success(domain.AccountLedgerTotals(
        debtorMinorUnits: readSum('debtor_minor'),
        creditorMinorUnits: readSum('creditor_minor'),
      ));
    } catch (error) {
      return Failure(_failure('customer_ledger_totals_failed', error));
    }
  }

  @override
  Future<Result<List<domain.AccountCurrencyLedgerTotals>>> sumLedgerSidesByCurrency(
    String query, {
    domain.AccountSqlFilter filter = domain.AccountSqlFilter.all,
    String membershipCurrencyCode = 'YER',
  }) async {
    try {
      final trimmed = query.trim();
      final like = '%$trimmed%';
      final filterName = filter.name;
      final rows = await database.customSelect(
        """
        SELECT
          cur.currency_code AS currency_code,
          COALESCE(SUM(CASE
            WHEN COALESCE(cur.signed_balance, 0) < 0 THEN -cur.signed_balance
            ELSE 0
          END), 0) AS debtor_minor,
          COALESCE(SUM(CASE
            WHEN COALESCE(cur.signed_balance, 0) > 0 THEN cur.signed_balance
            ELSE 0
          END), 0) AS creditor_minor
        FROM customers c
        LEFT JOIN (
          SELECT
            customer_id,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND currency_code = ?
            AND customer_id IS NOT NULL
          GROUP BY customer_id
        ) mem ON mem.customer_id = c.id
        JOIN (
          SELECT
            customer_id,
            currency_code,
            SUM(CASE
              WHEN type IN ('deposit', 'reward', 'reversal') THEN amount_minor_units
              ELSE -amount_minor_units
            END) AS signed_balance
          FROM transactions
          WHERE status = 'completed'
            AND customer_id IS NOT NULL
          GROUP BY customer_id, currency_code
        ) cur ON cur.customer_id = c.id
        WHERE c.status != 'merged'
          AND (
            ? = 'all'
            OR (? = 'debtor' AND COALESCE(mem.signed_balance, 0) < 0)
            OR (? = 'creditor' AND COALESCE(mem.signed_balance, 0) > 0)
            OR (? = 'zero' AND COALESCE(mem.signed_balance, 0) = 0)
            OR (? = 'provisional' AND c.status = 'provisional')
            OR (? = 'unlinked' AND NOT EXISTS (
              SELECT 1 FROM customer_identifiers i
              WHERE i.customer_id = c.id
                AND i.type = 'phoneNumber'
                AND TRIM(i.value) != ''
            ))
          )
          AND (
            ? = ''
            OR c.display_name LIKE ?
            OR EXISTS (
              SELECT 1 FROM customer_identifiers i2
              WHERE i2.customer_id = c.id AND i2.value LIKE ?
            )
          )
        GROUP BY cur.currency_code
        ORDER BY CASE WHEN cur.currency_code = 'YER' THEN 0 ELSE 1 END, cur.currency_code
        """,
        variables: [
          Variable.withString(membershipCurrencyCode),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(filterName),
          Variable.withString(trimmed),
          Variable.withString(like),
          Variable.withString(like),
        ],
        readsFrom: {
          database.customers,
          database.transactions,
          database.customerIdentifiers,
        },
      ).get();
      int readSum(QueryRow row, String name) {
        final value = row.data[name];
        if (value is int) return value;
        if (value is BigInt) return value.toInt();
        if (value is num) return value.toInt();
        return 0;
      }
      return Success([
        for (final row in rows)
          domain.AccountCurrencyLedgerTotals(
            currencyCode: row.read<String>('currency_code'),
            debtorMinorUnits: readSum(row, 'debtor_minor'),
            creditorMinorUnits: readSum(row, 'creditor_minor'),
          ),
      ]);
    } catch (error) {
      return Failure(_failure('customer_ledger_currency_totals_failed', error));
    }
  }


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
