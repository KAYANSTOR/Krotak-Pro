import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:net_app/data/database/app_database.dart';

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
}
