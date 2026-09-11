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
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get kind => text()();
  TextColumn get value => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {kind, value},
      ];
}

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get currencyCode => text()();
  IntColumn get balanceMinor => integer().withDefault(const Constant(0))();
  IntColumn get reservedMinor => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {customerId, currencyCode},
      ];
}

class CardCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get provider => text()();
  IntColumn get faceValueMinor => integer()();
  IntColumn get salePriceMinor => integer()();
  TextColumn get currencyCode => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(CardCategories, #id)();
  TextColumn get serial => text()();
  TextColumn get pin => text().nullable()();
  TextColumn get status => text()(); // available | reserved | sold
  TextColumn get reservedForCustomerId => text().nullable()();
  DateTimeColumn get reservedUntil => dateTime().nullable()();
  DateTimeColumn get soldAt => dateTime().nullable()();
  TextColumn get soldTransactionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {serial},
      ];
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  TextColumn get dedupeKey => text()();
  TextColumn get status => text()(); // received | parsed | processed | failed
  TextColumn get parseResultJson => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get processedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {dedupeKey},
      ];
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get type => text()();
  TextColumn get status => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get relatedEntityType => text().nullable()();
  TextColumn get relatedEntityId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Licenses extends Table {
  TextColumn get id => text()();
  TextColumn get status => text()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Customers,
  CustomerIdentifiers,
  Wallets,
  CardCategories,
  Cards,
  Messages,
  Transactions,
  AuditLogs,
  Settings,
  Licenses,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // future migrations
        },
      );
}
