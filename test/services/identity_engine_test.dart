import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, CustomerIdentifier;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/local_account_merge_service.dart';
import 'package:net_app/domain/services/local_customer_identity_resolver.dart';
import 'package:net_app/domain/services/local_customer_service.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalTransactionRepository transactions;
  late LocalAuditLogRepository auditLogs;
  late LocalCustomerService customerService;
  late LocalCustomerIdentityResolver resolver;
  late LocalAccountMergeService mergeService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    transactions = LocalTransactionRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    final uow = DriftUnitOfWork(database);
    final clock = FixedClock(DateTime.utc(2026, 9, 12));
    final ids = SequentialIdGenerator();
    customerService = LocalCustomerService(customers: customers, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
    resolver = LocalCustomerIdentityResolver(customers: customers);
    mergeService = LocalAccountMergeService(customers: customers, transactions: transactions, auditLogs: auditLogs, unitOfWork: uow, clock: clock, ids: ids);
  });

  tearDown(() async { await database.close(); });

  test('create stores canonical phone and resolves all formats', () async {
    final created = await customerService.create(displayName: 'عميل', identifierType: CustomerIdentifierType.phoneNumber, identifierValue: '0777123456');
    expect(created, isA<Success<Customer>>());
    final customer = (created as Success<Customer>).value;
    final ids = await customers.listIdentifiers(customer.id);
    final stored = (ids as Success).value.single.value;
    expect(stored, '777123456');
    for (final form in ['777123456', '0777123456', '+967777123456', '00967777123456']) {
      final found = await customers.findByIdentifier(form);
      expect((found as Success<Customer?>).value?.id, customer.id, reason: form);
      final resolution = await resolver.resolve(identifierValue: form, identifierType: TransferIdentifierType.phone);
      final r = (resolution as Success<CustomerIdentityResolution>).value;
      expect(r.isResolved, isTrue, reason: form);
      expect(r.customer?.id, customer.id, reason: form);
      expect(r.deliveryPhone, '777123456', reason: form);
    }
  });

  test('legacy stored international form still resolves via lookupKeys', () async {
    final created = await customerService.create(displayName: 'قديم', identifierType: CustomerIdentifierType.username, identifierValue: 'legacy-user');
    final customer = (created as Success<Customer>).value;
    await customers.saveIdentifier(CustomerIdentifier(id: 'id-legacy-phone', customerId: customer.id, type: CustomerIdentifierType.phoneNumber, value: '+967777999888', isPrimary: true));
    final found = await customers.findByIdentifier('0777999888');
    expect((found as Success<Customer?>).value?.id, customer.id);
  });

  test('merge moves identifiers; both phones resolve to survivor', () async {
    final a = (await customerService.create(displayName: 'أ', identifierType: CustomerIdentifierType.phoneNumber, identifierValue: '+967770000001') as Success<Customer>).value;
    final b = (await customerService.create(displayName: 'ب', identifierType: CustomerIdentifierType.phoneNumber, identifierValue: '770000002') as Success<Customer>).value;
    final merged = await mergeService.merge(sourceCustomerId: a.id, targetCustomerId: b.id);
    expect(merged, isA<Success<Customer>>());
    final bySourcePhone = await customers.findByIdentifier('0770000001');
    expect((bySourcePhone as Success<Customer?>).value?.id, b.id);
    final res = await resolver.resolve(identifierValue: '00967770000001', identifierType: TransferIdentifierType.phone);
    final r = (res as Success<CustomerIdentityResolution>).value;
    expect(r.isResolved, isTrue);
    expect(r.customer?.id, b.id);
    final audits = await auditLogs.findByEntity('customer', a.id);
    expect((audits as Success).value.any((e) => e.action == 'merged'), isTrue);
  });

  test('invalid phone create fails', () async {
    final r = await customerService.create(displayName: 'x', identifierType: CustomerIdentifierType.phoneNumber, identifierValue: '12');
    expect(r, isA<Failure<Customer>>());
  });
}
