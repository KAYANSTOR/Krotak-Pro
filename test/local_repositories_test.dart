import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart' as domain;
import 'package:net_app/domain/entities/customer.dart' as domain;
import 'package:net_app/domain/entities/message.dart' as domain;
import 'package:net_app/domain/entities/money.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and finds a customer by identifier', () async {
    final repository = LocalCustomerRepository(database);
    final now = DateTime(2026, 1, 1);
    final customer = domain.Customer(
      id: 'customer-1',
      displayName: 'Customer One',
      status: domain.CustomerStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    const identifier = domain.CustomerIdentifier(
      id: 'identifier-1',
      customerId: 'customer-1',
      type: domain.CustomerIdentifierType.phoneNumber,
      value: '700000000',
      isPrimary: true,
    );

    await repository.save(customer);
    await repository.saveIdentifier(identifier);
    final result = await repository.findByIdentifier('700000000');

    expect(result, isA<Success<domain.Customer?>>());
    expect((result as Success<domain.Customer?>).value?.id, 'customer-1');
  });

  test('reserves an available card atomically', () async {
    final repository = LocalCardRepository(database);
    await database.into(database.cards).insert(
          CardsCompanion.insert(
            id: 'card-1',
            categoryId: 'category-1',
            serialNumber: 'serial-1',
            secretCode: 'secret-1',
            status: 'available',
          ),
        );

    final result = await repository.reserve(
      'card-1',
      domain.CardReservation(
        reservationId: 'reservation-1',
        reservedAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 1, 0, 5),
      ),
    );

    expect(result, isA<Success<void>>());
    final card = await repository.findById('card-1');
    expect((card as Success<domain.Card?>).value?.status, domain.CardStatus.reserved);
  });

  test('stores a received message and lists it as pending', () async {
    final repository = LocalMessageRepository(database);
    final message = domain.IncomingMessage(
      id: 'message-1',
      sender: 'bank',
      body: 'transfer payload',
      receivedAt: DateTime(2026, 1, 1),
      status: domain.MessageProcessingStatus.received,
      externalReference: 'reference-1',
      customerIdentifier: '700000000',
    );

    await repository.save(message);
    final pending = await repository.pendingProcessing();

    expect((pending as Success<List<domain.IncomingMessage>>).value, hasLength(1));
    expect(pending.value.single.externalReference, 'reference-1');
  });

  test('keeps money values separate from repository persistence', () {
    const money = Money(minorUnits: 100, currencyCode: 'YER');

    expect(money.minorUnits, 100);
    expect(money.currencyCode, 'YER');
  });
}
