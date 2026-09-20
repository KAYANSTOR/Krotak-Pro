import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide PointOfSale, TransferTemplate;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/pos_profile.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_point_of_sale_profile_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';

void main() {
  late AppDatabase database;
  late LocalPointOfSaleProfileService profiles;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final customers = LocalCustomerRepository(database);
    final pointsOfSale = LocalPointOfSaleRepository(database);
    final wallets = LocalWalletRepository(database);
    final templates = LocalTransferTemplateRepository(database);
    final transactions = LocalTransactionRepository(database);
    final settings = LocalSettingsRepository(database);
    final auditLogs = LocalAuditLogRepository(database);
    final clock = FixedClock(DateTime(2026, 9, 20));
    final ids = SequentialIdGenerator();
    final uow = DriftUnitOfWork(database);
    final balances = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    profiles = LocalPointOfSaleProfileService(
      customers: customers,
      pointsOfSale: pointsOfSale,
      posRegistry: LocalPosAccountRegistry(
        settings: settings,
        clock: clock,
      ),
      templates: templates,
      auditLogs: auditLogs,
      unitOfWork: uow,
      balanceService: balances,
      clock: clock,
      ids: ids,
    );

    // Keep these references live for the local-repository construction above.
    expect(wallets, isA<LocalWalletRepository>());
  });

  tearDown(() => database.close());

  test('creates the complete POS profile atomically', () async {
    final result = await profiles.createPointOfSaleProfile(
      name: 'نقطة النور',
      phone: '771234567',
      creditLimitMinorUnits: 5000000,
      percentageMode: PosPercentageMode.defaultCategory,
    );

    expect(result, isA<Success<PointOfSaleProfile>>());
    final profile = (result as Success<PointOfSaleProfile>).value;

    expect(profile.pointOfSale.name, 'نقطة النور');
    expect(profile.account?.customerId, profile.customer?.id);
    expect(profile.account?.creditLimitMinorUnits, 5000000);
    expect(profile.account?.notifyPhone, '771234567');

    final templateResult = await LocalTransferTemplateRepository(database).listAll();
    expect(
      (templateResult as Success<List<TransferTemplate>>).value
          .where((t) => t.posId == profile.pointOfSale.id)
          .length,
      5,
    );
  });

  test('rejects duplicate POS name and phone before creating another profile', () async {
    final first = await profiles.createPointOfSaleProfile(
      name: 'نقطة الربيع',
      phone: '772345678',
      creditLimitMinorUnits: null,
      percentageMode: PosPercentageMode.zero,
    );
    expect(first, isA<Success<PointOfSaleProfile>>());

    final duplicateName = await profiles.createPointOfSaleProfile(
      name: 'نقطة الربيع',
      phone: '773456789',
      creditLimitMinorUnits: null,
      percentageMode: PosPercentageMode.zero,
    );
    expect(
      (duplicateName as Failure<PointOfSaleProfile>).error.code,
      'duplicate_pos_name',
    );

    final duplicatePhone = await profiles.createPointOfSaleProfile(
      name: 'نقطة أخرى',
      phone: '772345678',
      creditLimitMinorUnits: null,
      percentageMode: PosPercentageMode.zero,
    );
    expect(
      (duplicatePhone as Failure<PointOfSaleProfile>).error.code,
      'duplicate_pos_phone',
    );
  });

  test('updates POS and account from one lifecycle operation', () async {
    final created = await profiles.createPointOfSaleProfile(
      name: 'نقطة السلام',
      phone: '774567890',
      creditLimitMinorUnits: 1000000,
      percentageMode: PosPercentageMode.defaultCategory,
    );
    final original = (created as Success<PointOfSaleProfile>).value;

    final updated = await profiles.updatePointOfSaleProfile(
      id: original.pointOfSale.id,
      name: 'نقطة السلام الجديدة',
      phone: '775678901',
      creditLimitMinorUnits: 2500000,
      percentageMode: PosPercentageMode.zero,
      status: PointOfSaleStatus.suspended,
    );
    expect(updated, isA<Success<PointOfSaleProfile>>());

    final profile = (updated as Success<PointOfSaleProfile>).value;
    expect(profile.pointOfSale.id, original.pointOfSale.id);
    expect(profile.pointOfSale.name, 'نقطة السلام الجديدة');
    expect(profile.pointOfSale.status, PointOfSaleStatus.suspended);
    expect(profile.account?.name, 'نقطة السلام الجديدة');
    expect(profile.account?.status, PointOfSaleStatus.suspended);
    expect(profile.account?.notifyPhone, '775678901');
    expect(profile.account?.percentageMode, PosPercentageMode.zero);
    expect(profile.account?.creditLimitMinorUnits, 2500000);
  });

  test('archive synchronizes status and respects the read-model filter', () async {
    final created = await profiles.createPointOfSaleProfile(
      name: 'نقطة الشروق',
      phone: '776789012',
      creditLimitMinorUnits: null,
      percentageMode: PosPercentageMode.defaultCategory,
    );
    final original = (created as Success<PointOfSaleProfile>).value;

    final archived = await profiles.archivePointOfSale(original.pointOfSale.id);
    expect(archived, isA<Success<PointOfSaleProfile>>());
    expect(
      (archived as Success<PointOfSaleProfile>).value.pointOfSale.status,
      PointOfSaleStatus.archived,
    );

    final accountResult = await LocalPosAccountRegistry(
      settings: LocalSettingsRepository(database),
      clock: FixedClock(DateTime(2026, 9, 20)),
    ).findByPosId(original.pointOfSale.id);
    expect(
      (accountResult as Success<PosAccount?>).value?.status,
      PointOfSaleStatus.archived,
    );

    final visible = await profiles.listPointOfSaleProfiles(includeArchived: false);
    expect(
      (visible as Success<List<PointOfSaleProfile>>).value
          .any((p) => p.pointOfSale.id == original.pointOfSale.id),
      isFalse,
    );

    final all = await profiles.listPointOfSaleProfiles(includeArchived: true);
    expect(
      (all as Success<List<PointOfSaleProfile>>).value
          .any((p) => p.pointOfSale.id == original.pointOfSale.id),
      isTrue,
    );
  });

  test('lists a catalog POS even when its account binding is missing', () async {
    final points = LocalPointOfSaleRepository(database);
    final saved = await points.save(
      PointOfSale(
        id: 'pos-orphan',
        name: 'نقطة غير مكتملة',
        status: PointOfSaleStatus.active,
        createdAt: DateTime(2026, 9, 20),
      ),
    );
    expect(saved, isA<Success<void>>());

    final result = await profiles.listPointOfSaleProfiles();
    expect(result, isA<Success<List<PointOfSaleProfile>>>());

    final profile = (result as Success<List<PointOfSaleProfile>>).value
        .firstWhere((p) => p.pointOfSale.id == 'pos-orphan');
    expect(profile.isLinked, isFalse);
    expect(profile.account, isNull);
  });
}
