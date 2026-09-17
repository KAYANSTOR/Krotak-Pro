import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate;

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates schema version 4 and starts empty', () async {
    expect(database.schemaVersion, 4);
    expect(await database.select(database.customers).get(), isEmpty);
    expect(await database.select(database.cards).get(), isEmpty);
    expect(await database.select(database.incomingMessages).get(), isEmpty);
  });

  test('stores an incoming message before processing', () async {
    await database.into(database.incomingMessages).insert(
      IncomingMessagesCompanion.insert(
        id: 'message-1', sender: 'bank', body: 'transfer payload',
        receivedAt: DateTime(2026, 1, 1), status: 'received',
      ),
    );
    final messages = await database.select(database.incomingMessages).get();
    expect(messages.single.id, 'message-1');
    expect(messages.single.status, 'received');
  });

  test('enforces unique customer identifiers and card serials', () async {
    await database.into(database.customers).insert(
      CustomersCompanion.insert(
        id: 'customer-1', displayName: 'Ali', status: 'active',
        createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await database.into(database.customerIdentifiers).insert(
      CustomerIdentifiersCompanion.insert(
        id: 'identifier-1', customerId: 'customer-1',
        type: 'phoneNumber', value: '733000000',
      ),
    );
    await expectLater(
      database.into(database.customerIdentifiers).insert(
        CustomerIdentifiersCompanion.insert(
          id: 'identifier-2', customerId: 'customer-1',
          type: 'phoneNumber', value: '733000000',
        ),
      ), throwsA(isA<Exception>()),
    );

    await database.into(database.cards).insert(
      CardsCompanion.insert(
        id: 'card-1', categoryId: 'cat-1', serialNumber: 'A-1',
        secretCode: 'secret-1', status: 'available',
      ),
    );
    await expectLater(
      database.into(database.cards).insert(
        CardsCompanion.insert(
          id: 'card-2', categoryId: 'cat-1', serialNumber: 'A-1',
          secretCode: 'secret-2', status: 'available',
        ),
      ), throwsA(isA<Exception>()),
    );
  });

  test('phase2: unique reservation_id prevents double reservation key', () async {
    await database.into(database.cards).insert(
      CardsCompanion.insert(
        id: 'card-r1', categoryId: 'cat-1', serialNumber: 'R-1',
        secretCode: 'sec-r1', status: 'reserved',
        reservationId: const Value('res-1'),
        reservedAt: Value(DateTime(2026, 9, 17)),
        reservationExpiresAt: Value(DateTime(2026, 9, 17, 1)),
      ),
    );
    await expectLater(
      database.into(database.cards).insert(
        CardsCompanion.insert(
          id: 'card-r2', categoryId: 'cat-1', serialNumber: 'R-2',
          secretCode: 'sec-r2', status: 'reserved',
          reservationId: const Value('res-1'),
          reservedAt: Value(DateTime(2026, 9, 17)),
          reservationExpiresAt: Value(DateTime(2026, 9, 17, 1)),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('phase2: unique external_reference on messages', () async {
    await database.into(database.incomingMessages).insert(
      IncomingMessagesCompanion.insert(
        id: 'm1', sender: 'JAIB', body: 'body1',
        receivedAt: DateTime(2026, 9, 17), status: 'received',
        externalReference: const Value('ref-100'),
      ),
    );
    await expectLater(
      database.into(database.incomingMessages).insert(
        IncomingMessagesCompanion.insert(
          id: 'm2', sender: 'JAIB', body: 'body2',
          receivedAt: DateTime(2026, 9, 17), status: 'received',
          externalReference: const Value('ref-100'),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('phase2: unique transaction reference', () async {
    await database.into(database.transactions).insert(
      TransactionsCompanion.insert(
        id: 'tx1', type: 'deposit', status: 'completed',
        amountMinorUnits: 1000, currencyCode: 'YER',
        createdAt: DateTime(2026, 9, 17),
        reference: const Value('op-1'),
      ),
    );
    await expectLater(
      database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx2', type: 'deposit', status: 'completed',
          amountMinorUnits: 500, currencyCode: 'YER',
          createdAt: DateTime(2026, 9, 17),
          reference: const Value('op-1'),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('phase2: one sale row per card_id', () async {
    await database.into(database.sales).insert(
      SalesCompanion.insert(
        id: 'sale-1', customerId: 'c1', cardId: 'card-x',
        amountMinorUnits: 100, currencyCode: 'YER',
        status: 'completed', createdAt: DateTime(2026, 9, 17),
      ),
    );
    await expectLater(
      database.into(database.sales).insert(
        SalesCompanion.insert(
          id: 'sale-2', customerId: 'c1', cardId: 'card-x',
          amountMinorUnits: 100, currencyCode: 'YER',
          status: 'completed', createdAt: DateTime(2026, 9, 17),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
