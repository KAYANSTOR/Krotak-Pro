import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, PointOfSale;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalSettingsRepository settings;
  late LocalPointOfSaleRepository pointsOfSale;
  late LocalAuditLogRepository audit;
  late LocalCustomerService customerService;
  late LocalPosAccountRegistry registry;
  late FixedClock clock;
  late SequentialIdGenerator ids;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    settings = LocalSettingsRepository(database);
    pointsOfSale = LocalPointOfSaleRepository(database);
    audit = LocalAuditLogRepository(database);
    clock = FixedClock(DateTime(2026, 9, 17, 12));
    ids = SequentialIdGenerator();
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: audit,
      unitOfWork: DriftUnitOfWork(database),
      clock: clock,
      ids: ids,
    );
    registry = LocalPosAccountRegistry(
      settings: settings,
      clock: clock,
      customers: customers,
      customerService: customerService,
      pointsOfSale: pointsOfSale,
      ids: ids,
    );
  });

  tearDown(() => database.close());

  test('empty customerId is resolved to a real ledger customer', () async {
    final savedPos = await pointsOfSale.save(
      PointOfSale(
        id: 'pos-1',
        name: 'كشك النور',
        status: PointOfSaleStatus.active,
        createdAt: clock.now(),
      ),
    );
    expect(savedPos, isA<Success<void>>());

    final result = await registry.save(
      const PosAccount(
        posId: 'pos-1',
        customerId: '',
        name: 'كشك النور',
        identifiers: ['كشك النور'],
      ),
    );

    expect(result, isA<Success<void>>());
    final binding = await registry.findByPosId('pos-1');
    expect(binding, isA<Success<PosAccount?>>());
    final account = (binding as Success<PosAccount?>).value!;
    expect(account.customerId, isNotEmpty);
    expect(account.identifiers, contains('كشك النور'));

    final customer = await customers.findByIdentifier('pos:pos-1');
    expect(customer, isA<Success<Customer?>>());
    expect((customer as Success<Customer?>).value?.id, account.customerId);
  });
}
