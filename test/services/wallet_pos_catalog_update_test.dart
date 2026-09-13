import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';

void main() {
  late AppDatabase database;
  late LocalWalletCatalogService wallets;
  late LocalPointOfSaleCatalogService points;
  late LocalWalletRepository walletRepo;
  late LocalPointOfSaleRepository posRepo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    walletRepo = LocalWalletRepository(database);
    posRepo = LocalPointOfSaleRepository(database);
    final audit = LocalAuditLogRepository(database);
    final clock = FixedClock(DateTime(2026, 9, 13));
    final ids = SequentialIdGenerator();
    wallets = LocalWalletCatalogService(
      wallets: walletRepo,
      auditLogs: audit,
      clock: clock,
      ids: ids,
    );
    points = LocalPointOfSaleCatalogService(
      pointsOfSale: posRepo,
      auditLogs: audit,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('updates wallet name and status without changing id', () async {
    final created = await wallets.saveWallet(name: 'جيب');
    final wallet = (created as Success<Wallet>).value;

    final updated = await wallets.updateWallet(
      id: wallet.id,
      name: 'جيب المحدث',
      status: WalletStatus.suspended,
    );
    expect(updated, isA<Success<Wallet>>());
    final value = (updated as Success<Wallet>).value;
    expect(value.id, wallet.id);
    expect(value.name, 'جيب المحدث');
    expect(value.status, WalletStatus.suspended);

    final stored = await walletRepo.findById(wallet.id);
    expect((stored as Success<Wallet?>).value?.name, 'جيب المحدث');
  });

  test('rejects empty wallet rename', () async {
    final created = await wallets.saveWallet(name: 'جوالي');
    final wallet = (created as Success<Wallet>).value;
    final result = await wallets.updateWallet(
      id: wallet.id,
      name: '   ',
      status: WalletStatus.active,
    );
    expect((result as Failure<Wallet>).error.code, 'invalid_wallet_name');
  });

  test('updates point of sale name and status', () async {
    final created = await points.savePointOfSale(name: 'كشك النور');
    final pos = (created as Success<PointOfSale>).value;

    final updated = await points.updatePointOfSale(
      id: pos.id,
      name: 'كشك النور 2',
      status: PointOfSaleStatus.archived,
    );
    final value = (updated as Success<PointOfSale>).value;
    expect(value.id, pos.id);
    expect(value.name, 'كشك النور 2');
    expect(value.status, PointOfSaleStatus.archived);
  });

  test('missing catalog items fail with not found', () async {
    final wallet = await wallets.updateWallet(
      id: 'missing',
      name: 'x',
      status: WalletStatus.active,
    );
    expect((wallet as Failure<Wallet>).error.code, 'wallet_not_found');

    final pos = await points.updatePointOfSale(
      id: 'missing',
      name: 'x',
      status: PointOfSaleStatus.active,
    );
    expect((pos as Failure<PointOfSale>).error.code, 'pos_not_found');
  });
}
