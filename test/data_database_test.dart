import 'package:flutter_test/flutter_test.dart';
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

  test('creates schema version one and starts empty', () async {
    expect(database.schemaVersion, 1);
    expect(await database.select(database.customers).get(), isEmpty);
    expect(await database.select(database.cards).get(), isEmpty);
    expect(await database.select(database.incomingMessages).get(), isEmpty);
  });

  test('stores an incoming message before processing', () async {
    await database.into(database.incomingMessages).insert(
          IncomingMessagesCompanion.insert(
            id: 'message-1',
            sender: 'bank',
            body: 'transfer payload',
            receivedAt: DateTime(2026, 1, 1),
            status: 'received',
          ),
        );

    final messages = await database.select(database.incomingMessages).get();

    expect(messages.single.id, 'message-1');
    expect(messages.single.status, 'received');
  });

  test('enforces unique customer identifiers and card serials', () async {
    await database.into(database.customers).insert(
          CustomersCompanion.insert(
            id: 'customer-1',
            displayName: 'Ali',
            status: 'active',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    await database.into(database.customerIdentifiers).insert(
          CustomerIdentifiersCompanion.insert(
            id: 'identifier-1',
            customerId: 'customer-1',
            type: 'phoneNumber',
            value: '733000000',
          ),
        );

    await expectLater(
      database.into(database.customerIdentifiers).insert(
            CustomerIdentifiersCompanion.insert(
              id: 'identifier-2',
              customerId: 'customer-1',
              type: 'phoneNumber',
              value: '733000000',
            ),
          ),
      throwsA(isA<Exception>()),
    );

    await database.into(database.cards).insert(
          CardsCompanion.insert(
            id: 'card-1',
            categoryId: 'cat-1',
            serialNumber: 'A-1',
            secretCode: 'secret-1',
            status: 'available',
          ),
        );

    await expectLater(
      database.into(database.cards).insert(
            CardsCompanion.insert(
              id: 'card-2',
              categoryId: 'cat-1',
              serialNumber: 'A-1',
              secretCode: 'secret-2',
              status: 'available',
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });
}
