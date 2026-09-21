import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, PointOfSale, TransferTemplate;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/domain/services/local_pos_profile_service.dart';
import 'package:net_app/domain/services/default_pos_templates_seeder.dart';

void main() {
  late AppDatabase database;
  late LocalPosProfileService profiles;
  late LocalPointOfSaleRepository posRepo;
  late LocalTransferTemplateRepository templates;
  late LocalCustomerService customerService;
  late LocalCustomerRepository customers;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    posRepo = LocalPointOfSaleRepository(database);
    templates = LocalTransferTemplateRepository(database);
    final audit = LocalAuditLogRepository(database);
    final settings = LocalSettingsRepository(database);
    customers = LocalCustomerRepository(database);
    final clock = FixedClock(DateTime(2026, 9, 20));
    final ids = SequentialIdGenerator();
    final catalog = LocalPointOfSaleCatalogService(
      pointsOfSale: posRepo,
      auditLogs: audit,
      clock: clock,
      ids: ids,
    );
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: audit,
      unitOfWork: DriftUnitOfWork(database),
      clock: clock,
      ids: ids,
    );
    profiles = LocalPosProfileService(
      posCatalog: catalog,
      posRegistry: LocalPosAccountRegistry(settings: settings, clock: clock),
      pointsOfSale: posRepo,
      customers: customers,
      customerService: customerService,
      templates: templates,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('create seeds the full POS template catalog and binds ledger phone', () async {
    final created = await profiles.create(
      name: 'كشك النور',
      phone: '779776919',
      creditLimitMinorUnits: 5000000,
    );
    expect(created, isA<Success<PosProfile>>());
    final profile = (created as Success<PosProfile>).value;
    expect(profile.pointOfSale.name, 'كشك النور');
    expect(profile.account.notifyPhone, isNotEmpty);
    expect(profile.account.creditLimitMinorUnits, 5000000);

    final listed = await templates.listAll();
    final all = (listed as Success).value as List;
    final forPos = all.where((t) => t.posId == profile.pointOfSale.id).toList();
    expect(forPos.length, DefaultPosTemplatesSeeder.catalogSize);
  });

  test('rejects duplicate POS name', () async {
    final first = await profiles.create(name: 'كشك', phone: '779000001');
    expect(first, isA<Success<PosProfile>>());
    final second = await profiles.create(name: 'كشك', phone: '779000002');
    expect(second, isA<Failure<PosProfile>>());
    expect((second as Failure<PosProfile>).error.message, contains('بنفس الاسم'));
  });

  test('links a new POS to an existing customer account instead of rejecting', () async {
    final existing = await customerService.create(
      displayName: 'عميل قائم',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '779111222',
    );
    final customerId = (existing as Success<Customer>).value.id;

    final created = await profiles.create(name: 'نقطة', phone: '779111222');

    expect(created, isA<Success<PosProfile>>());
    final profile = (created as Success<PosProfile>).value;
    // نفس حساب الدفتر — لا يُنشأ حساب ثانٍ بنفس الرقم.
    expect(profile.account.customerId, customerId);
    final all = await customers.search('');
    expect((all as Success<List<Customer>>).value.length, 1);
  });

  test('update still refuses moving a POS onto another customer phone', () async {
    await customerService.create(
      displayName: 'عميل آخر',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '779777888',
    );
    final created = await profiles.create(name: 'نقطة تعديل', phone: '779123123');
    final profile = (created as Success<PosProfile>).value;

    final updated = await profiles.update(
      posId: profile.pointOfSale.id,
      status: PointOfSaleStatus.active,
      name: 'نقطة تعديل',
      phone: '779777888',
      existingAccount: profile.account,
    );

    expect(updated, isA<Failure<PosProfile>>());
    expect((updated as Failure<PosProfile>).error.message, contains('عميل'));
  });

  test('rejects phone already bound to another POS', () async {
    final first = await profiles.create(name: 'أولى', phone: '779333444');
    expect(first, isA<Success<PosProfile>>());
    final second = await profiles.create(name: 'ثانية', phone: '779333444');
    expect(second, isA<Failure<PosProfile>>());
    expect((second as Failure<PosProfile>).error.message, contains('نقطة بيع أخرى'));
  });

  test('update keeps id and changes name and phone', () async {
    final created = await profiles.create(name: 'قديم', phone: '779555666');
    final profile = (created as Success<PosProfile>).value;
    final updated = await profiles.update(
      posId: profile.pointOfSale.id,
      status: PointOfSaleStatus.active,
      name: 'جديد',
      phone: '779555667',
      existingAccount: profile.account,
      percentageMode: PosPercentageMode.zero,
    );
    expect(updated, isA<Success<PosProfile>>());
    final next = (updated as Success<PosProfile>).value;
    expect(next.pointOfSale.id, profile.pointOfSale.id);
    expect(next.pointOfSale.name, 'جديد');
    expect(next.account.percentageMode, PosPercentageMode.zero);
  });

  test('backfill adds missing templates without re-activating a disabled one', () async {
    final created = await profiles.create(name: 'نقطة قديمة', phone: '779555444');
    final profile = (created as Success<PosProfile>).value;
    final listed = await templates.listAll();
    final forPos = (listed as Success<List<TransferTemplate>>)
        .value
        .where((t) => t.posId == profile.pointOfSale.id)
        .toList();
    expect(forPos.length, DefaultPosTemplatesSeeder.catalogSize);

    // إصدار قديم: قالب أوقفه المشغّل + قالب ناقص من الكتالوج.
    final disabled = forPos.first;
    await templates.save(disabled.copyWith(isActive: false));
    await templates.delete(forPos.last.id);

    final back = await profiles.ensureInboundTemplates(
      posId: profile.pointOfSale.id,
      posName: 'نقطة قديمة',
    );
    expect(back, isA<Success<int>>());
    // يُضاف الناقص فقط: 1 في هذا السيناريو.
    expect((back as Success<int>).value, 1);

    final after = await templates.listAll();
    final afterPos = (after as Success<List<TransferTemplate>>)
        .value
        .where((t) => t.posId == profile.pointOfSale.id)
        .toList();
    expect(afterPos.length, DefaultPosTemplatesSeeder.catalogSize);
    expect(afterPos.firstWhere((t) => t.id == disabled.id).isActive, isFalse);
  });
}
