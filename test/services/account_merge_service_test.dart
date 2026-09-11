import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/services/local_account_merge_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalTransactionRepository transactions;
  late LocalAuditLogRepository auditLogs;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalAccountMergeService mergeService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    transactions = LocalTransactionRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 1, 1, 12));
    ids = SequentialIdGenerator();
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    mergeService = LocalAccountMergeService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> create(String name, String phone) async {
    final r = await customerService.create(
      displayName: name,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    return (r as Success<Customer>).value;
  }

  test('merges source into target and moves identifiers', () async {
    final a = await create('أ', '770000001');
    final b = await create('ب', '770000002');

    final merged = await mergeService.merge(
      sourceCustomerId: a.id,
      targetCustomerId: b.id,
    );
    expect(merged, isA<Success<Customer>>());
    final source = (merged as Success<Customer>).value;
    expect(source.status, CustomerStatus.merged);
    expect(source.mergedIntoId, b.id);

    final byOldPhone = await customers.findByIdentifier('770000001');
    expect((byOldPhone as Success<Customer?>).value?.id, b.id);

    final audits = await auditLogs.findByEntity('customer', a.id);
    expect((audits as Success).value, isNotEmpty);
  });

  test('merge is idempotent for same pair', () async {
    final a = await create('أ', '770000011');
    final b = await create('ب', '770000012');
    final first = await mergeService.merge(
      sourceCustomerId: a.id,
      targetCustomerId: b.id,
    );
    final second = await mergeService.merge(
      sourceCustomerId: a.id,
      targetCustomerId: b.id,
    );
    expect(first, isA<Success<Customer>>());
    expect(second, isA<Success<Customer>>());
    expect(
      (second as Success<Customer>).value.mergedIntoId,
      (first as Success<Customer>).value.mergedIntoId,
    );
  });

  test('rejects merge into self', () async {
    final a = await create('أ', '770000021');
    final r = await mergeService.merge(
      sourceCustomerId: a.id,
      targetCustomerId: a.id,
    );
    expect((r as Failure<Customer>).error.code, 'merge_same_customer');
  });

  test('rejects blacklisted source', () async {
    final a = await create('أ', '770000031');
    final b = await create('ب', '770000032');
    await customerService.blacklist(a.id);
    final r = await mergeService.merge(
      sourceCustomerId: a.id,
      targetCustomerId: b.id,
    );
    expect((r as Failure<Customer>).error.code, 'source_not_mergeable');
  });
}
