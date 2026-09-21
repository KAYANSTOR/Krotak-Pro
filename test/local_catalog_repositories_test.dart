import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krotak_pro/core/result.dart';
import 'package:krotak_pro/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate;
import 'package:krotak_pro/data/repositories/local_repositories.dart';
import 'package:krotak_pro/domain/entities/card.dart' as domain;
import 'package:krotak_pro/domain/entities/customer.dart' as domain;
import 'package:krotak_pro/domain/entities/money.dart';
import 'package:krotak_pro/domain/entities/transaction.dart' as domain;
import 'package:krotak_pro/domain/entities/wallet.dart' as domain;

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('saves wallets, points of sale, and card categories', () async {
    final wallets = LocalWalletRepository(database);
    final points = LocalPointOfSaleRepository(database);
    final categories = LocalCardCategoryRepository(database);
    final now = DateTime(2026, 1, 1);

    await wallets.save(
      domain.Wallet(
        id: 'wallet-1',
        name: 'Main',
        status: domain.WalletStatus.active,
        createdAt: now,
      ),
    );
    await points.save(
      domain.PointOfSale(
        id: 'pos-1',
        name: 'Shop',
        status: domain.PointOfSaleStatus.active,
        createdAt: now,
      ),
    );
    await categories.save(
      const domain.CardCategory(
        id: 'cat-1',
        name: 'Yemen Mobile 500',
        faceValue: Money(minorUnits: 500, currencyCode: 'YER'),
        isActive: true,
      ),
    );

    final wallet = await wallets.findById('wallet-1');
    final pos = await points.findById('pos-1');
    final category = await categories.findById('cat-1');

    expect((wallet as Success<domain.Wallet?>).value?.name, 'Main');
    expect((pos as Success<domain.PointOfSale?>).value?.name, 'Shop');
    expect(
      (category as Success<domain.CardCategory?>).value?.faceValue,
      const Money(minorUnits: 500, currencyCode: 'YER'),
    );
  });

  test('persists wallet payment source metadata used by inbound trust checks', () async {
    final wallets = LocalWalletRepository(database);
    final now = DateTime(2026, 1, 1);

    await wallets.save(
      domain.Wallet(
        id: 'wallet-source',
        name: 'JIB',
        status: domain.WalletStatus.active,
        createdAt: now,
        senderId: 'JIB',
        sourceMode: domain.WalletSourceMode.notification,
        packageName: 'com.wallet.jib',
      ),
    );

    final found = await wallets.findById('wallet-source');
    expect(found, isA<Success<domain.Wallet?>>());
    final wallet = (found as Success<domain.Wallet?>).value;
    expect(wallet, isNotNull);
    expect(wallet!.senderId, 'JIB');
    expect(wallet.sourceMode, domain.WalletSourceMode.notification);
    expect(wallet.packageName, 'com.wallet.jib');
  });

  test('rejects duplicate card serial numbers', () async {
    final cards = LocalCardRepository(database);
    const first = domain.Card(
      id: 'card-1',
      categoryId: 'cat-1',
      serialNumber: 'A-1',
      secretCode: 'secret-1',
      status: domain.CardStatus.available,
    );
    const second = domain.Card(
      id: 'card-2',
      categoryId: 'cat-1',
      serialNumber: 'A-1',
      secretCode: 'secret-2',
      status: domain.CardStatus.available,
    );

    expect(await cards.save(first), isA<Success<void>>());
    final duplicate = await cards.save(second);
    expect(duplicate, isA<Failure<void>>());
    expect((duplicate as Failure<void>).error.code, 'duplicate_serial');
  });

  test('appends transactions and finds them by customer and reference', () async {
    final repository = LocalTransactionRepository(database);
    final transaction = domain.Transaction(
      id: 'txn-1',
      type: domain.TransactionType.deposit,
      status: domain.TransactionStatus.completed,
      amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
      createdAt: DateTime(2026, 1, 1),
      customerId: 'customer-1',
      reference: 'ref-1',
    );

    await repository.append(transaction);
    final byCustomer = await repository.findByCustomer('customer-1');
    final byReference = await repository.findByReference('ref-1');

    expect((byCustomer as Success<List<domain.Transaction>>).value, hasLength(1));
    expect((byReference as Success<domain.Transaction?>).value?.id, 'txn-1');
  });

  test('releases an expired reservation back to available stock', () async {
    final cards = LocalCardRepository(database);
    await cards.save(
      const domain.Card(
        id: 'card-1',
        categoryId: 'cat-1',
        serialNumber: 'A-1',
        secretCode: 'secret-1',
        status: domain.CardStatus.available,
      ),
    );
    await cards.reserve(
      'card-1',
      domain.CardReservation(
        reservationId: 'res-1',
        reservedAt: DateTime(2026, 1, 1, 0, 0),
        expiresAt: DateTime(2026, 1, 1, 0, 5),
      ),
    );

    final expired = await cards.expireReservations(DateTime(2026, 1, 1, 0, 6));
    final card = await cards.findById('card-1');

    expect((expired as Success<int>).value, 1);
    expect((card as Success<domain.Card?>).value?.status, domain.CardStatus.available);
  });

  test('searches customers by identifier as well as name', () async {
    final customers = LocalCustomerRepository(database);
    final now = DateTime(2026, 1, 1);
    await customers.save(
      domain.Customer(
        id: 'customer-1',
        displayName: 'Ali',
        status: domain.CustomerStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await customers.saveIdentifier(
      const domain.CustomerIdentifier(
        id: 'id-1',
        customerId: 'customer-1',
        type: domain.CustomerIdentifierType.phoneNumber,
        value: '733000000',
        isPrimary: true,
      ),
    );

    final result = await customers.search('733');
    expect((result as Success<List<domain.Customer>>).value.single.id, 'customer-1');
  });
}
