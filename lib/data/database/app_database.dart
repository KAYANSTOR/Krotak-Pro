import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get status => text()();
  TextColumn get mergedIntoId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerIdentifiers extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();
  TextColumn get value => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PointOfSales extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CardCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get faceValueMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  TextColumn get serialNumber => text()();
  TextColumn get secretCode => text()();
  TextColumn get status => text()();
  TextColumn get reservationId => text().nullable()();
  DateTimeColumn get reservedAt => dateTime().nullable()();
  DateTimeColumn get reservationExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get status => text()();
  IntColumn get amountMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get customerId => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get relatedTransactionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get cardId => text()();
  IntColumn get amountMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TransferTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get pattern => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class IncomingMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get externalReference => text().nullable()();
  TextColumn get customerIdentifier => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Licenses extends Table {
  TextColumn get id => text()();
  TextColumn get status => text()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get deviceBinding => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Customers,
    CustomerIdentifiers,
    Wallets,
    PointOfSales,
    CardCategories,
    Cards,
    Transactions,
    Sales,
    TransferTemplates,
    IncomingMessages,
    Licenses,
    AppSettings,
    AuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async {
          await migrator.createAll();
          await _ensureTransferTemplateColumns();
          await _createIdempotencyIndexes();
        },
        onUpgrade: (Migrator migrator, int from, int to) async {
          // Never wipe data. All steps are additive / IF NOT EXISTS / best-effort.
          if (from < 2) {
            await _ensureTransferTemplateColumns();
          }
          if (from < 3) {
            await _createIdempotencyIndexes();
          }
          if (from < 4) {
            // Fix unique index on secret_code that broke upgrades when multiple
            // serial-only cards share empty secret ('').
            await customStatement(
              'DROP INDEX IF EXISTS idx_cards_secret_code',
            );
            await _createIdempotencyIndexes();
            await _ensureTransferTemplateColumns();
          }
        },
        beforeOpen: (details) async {
          await _ensureTransferTemplateColumns();
          await _createIdempotencyIndexes();
        },
      );

  Future<void> _ensureTransferTemplateColumns() async {
    await _addColumnIfMissing('transfer_templates', 'wallet_id', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'priority',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing('transfer_templates', 'sample_body', 'TEXT');
    await _addColumnIfMissing('transfer_templates', 'sender_code', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'identifier_kind',
      "TEXT NOT NULL DEFAULT 'phone'",
    );
  }

  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String typeSql,
  ) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    final exists = rows.any((r) => r.read<String>('name') == column);
    if (exists) return;
    await customStatement('ALTER TABLE $table ADD COLUMN $column $typeSql');
  }

  /// Unique indexes (idempotency). Partial indexes allow multiple NULLs/empties.
  Future<void> _createIdempotencyIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_identifiers_value '
      'ON customer_identifiers (value)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_serial_number '
      'ON cards (serial_number)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_secret_code '
      'ON cards (secret_code) '
      "WHERE secret_code IS NOT NULL AND secret_code != ''",
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_reservation_id '
      'ON cards (reservation_id) WHERE reservation_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_incoming_messages_external_reference '
      'ON incoming_messages (external_reference) '
      'WHERE external_reference IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_reference '
      'ON transactions (reference) WHERE reference IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_card_id '
      'ON sales (card_id)',
    );
  }
}
