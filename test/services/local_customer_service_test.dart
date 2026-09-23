import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/services/local_customer_service.dart';

/// اختبارات وحدة LocalCustomerService — كل عقود CustomerService.
void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalAuditLogRepository auditLogs;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 22, 15, 30));
    ids = SequentialIdGenerator();
    service = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<AuditLog>> auditsFor(String customerId) async {
    final r = await auditLogs.findByEntity('customer', customerId);
    return (r as Success<List<AuditLog>>).value;
  }

  group('create', () {
    test('creates active customer with phone and audits', () async {
      final r = await service.create(
        displayName: '  أحمد  ',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '0777123456',
      );
      expect(r, isA<Success<Customer>>());
      final c = (r as Success<Customer>).value;
      expect(c.displayName, 'أحمد');
      expect(c.status, CustomerStatus.active);
      expect(c.createdAt, clock.now());

      final found = await customers.findByIdentifier('777123456');
      expect((found as Success<Customer?>).value?.id, c.id);

      final audits = await auditsFor(c.id);
      expect(audits.any((a) => a.action == 'created'), isTrue);
    });

    test('creates provisional when status requested', () async {
      final r = await service.create(
        displayName: 'مؤقت',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733000111',
        status: CustomerStatus.provisional,
      );
      expect(r, isA<Success<Customer>>());
      expect((r as Success<Customer>).value.status, CustomerStatus.provisional);
    });

    test('rejects empty display name', () async {
      final r = await service.create(
        displayName: '   ',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733000222',
      );
      expect(r, isA<Failure<Customer>>());
      expect((r as Failure<Customer>).error.code, 'invalid_display_name');
    });

    test('rejects empty identifier', () async {
      final r = await service.create(
        displayName: 'بدون رقم',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '  ',
      );
      expect(r, isA<Failure<Customer>>());
      expect((r as Failure<Customer>).error.code, 'invalid_identifier');
    });

    test('rejects invalid phone', () async {
      final r = await service.create(
        displayName: 'رقم سيء',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '12',
      );
      expect(r, isA<Failure<Customer>>());
      expect((r as Failure<Customer>).error.code, 'invalid_phone_identifier');
    });

    test('rejects duplicate identifier', () async {
      final first = await service.create(
        displayName: 'أول',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733111222',
      );
      expect(first, isA<Success<Customer>>());

      final second = await service.create(
        displayName: 'ثاني',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733111222',
      );
      expect(second, isA<Failure<Customer>>());
      expect((second as Failure<Customer>).error.code, 'duplicate_identifier');
    });

    test('allows username identifier without phone rules', () async {
      final r = await service.create(
        displayName: 'مستخدم',
        identifierType: CustomerIdentifierType.username,
        identifierValue: 'shop-user-1',
      );
      expect(r, isA<Success<Customer>>());
      final found = await customers.findByIdentifier('shop-user-1');
      expect((found as Success<Customer?>).value, isNotNull);
    });
  });

  group('promoteToActive', () {
    test('promotes provisional to active and audits', () async {
      final created = await service.create(
        displayName: 'دفتر مؤقت',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733444555',
        status: CustomerStatus.provisional,
      );
      final id = (created as Success<Customer>).value.id;

      final promoted = await service.promoteToActive(id);
      expect(promoted, isA<Success<Customer>>());
      expect((promoted as Success<Customer>).value.status, CustomerStatus.active);

      final audits = await auditsFor(id);
      expect(audits.any((a) => a.action == 'promoted_to_active'), isTrue);
    });

    test('returns same customer when already active', () async {
      final created = await service.create(
        displayName: 'نشط',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733666777',
      );
      final id = (created as Success<Customer>).value.id;
      final again = await service.promoteToActive(id);
      expect(again, isA<Success<Customer>>());
      expect((again as Success<Customer>).value.status, CustomerStatus.active);
    });

    test('fails when customer missing', () async {
      final r = await service.promoteToActive('no-such-id');
      expect(r, isA<Failure<Customer>>());
      expect((r as Failure<Customer>).error.code, 'customer_not_found');
    });

    test('fails when blacklisted (not promotable)', () async {
      final created = await service.create(
        displayName: 'سيُحظر',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733888999',
      );
      final id = (created as Success<Customer>).value.id;
      await service.blacklist(id);

      final r = await service.promoteToActive(id);
      expect(r, isA<Failure<Customer>>());
      expect((r as Failure<Customer>).error.code, 'customer_not_promotable');
    });
  });

  group('blacklist', () {
    test('blacklists active customer and audits', () async {
      final created = await service.create(
        displayName: 'للحظر',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '734000111',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.blacklist(id);
      expect(r, isA<Success<void>>());

      final found = await customers.findById(id);
      expect((found as Success<Customer?>).value?.status, CustomerStatus.blacklisted);

      final audits = await auditsFor(id);
      expect(audits.any((a) => a.action == 'blacklisted'), isTrue);
    });

    test('fails when customer missing', () async {
      final r = await service.blacklist('missing');
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'customer_not_found');
    });
  });

  group('addIdentifier', () {
    test('adds secondary phone identifier', () async {
      final created = await service.create(
        displayName: 'متعدد',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '735111222',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.addIdentifier(
        customerId: id,
        type: CustomerIdentifierType.phoneNumber,
        value: '735333444',
        isPrimary: false,
      );
      expect(r, isA<Success<void>>());

      final idsResult = await customers.listIdentifiers(id);
      final list = (idsResult as Success<List<CustomerIdentifier>>).value;
      expect(list.length, greaterThanOrEqualTo(2));
      expect(
        list.any((i) => i.value.contains('735333444')),
        isTrue,
      );
    });

    test('rejects empty identifier value', () async {
      final created = await service.create(
        displayName: 'x',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '736111222',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.addIdentifier(
        customerId: id,
        type: CustomerIdentifierType.username,
        value: '  ',
        isPrimary: false,
      );
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'invalid_identifier');
    });

    test('rejects invalid phone identifier', () async {
      final created = await service.create(
        displayName: 'y',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '736222333',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.addIdentifier(
        customerId: id,
        type: CustomerIdentifierType.phoneNumber,
        value: '99',
        isPrimary: false,
      );
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'invalid_phone_identifier');
    });
  });

  group('bindPrimaryGsm', () {
    test('binds phone to username-only active customer', () async {
      final created = await service.create(
        displayName: 'بدون جوال',
        identifierType: CustomerIdentifierType.username,
        identifierValue: 'user-no-phone',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.bindPrimaryGsm(
        customerId: id,
        phone: '737000111',
      );
      expect(r, isA<Success<void>>());

      final found = await customers.findByIdentifier('737000111');
      expect((found as Success<Customer?>).value?.id, id);

      final audits = await auditsFor(id);
      expect(audits.any((a) => a.action == 'bind_primary_gsm'), isTrue);
    });

    test('no-op success when customer already has a phone', () async {
      final created = await service.create(
        displayName: 'لديه جوال',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '737111222',
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.bindPrimaryGsm(
        customerId: id,
        phone: '737999888',
      );
      expect(r, isA<Success<void>>());

      // الرقم الأصلي يبقى مربوطاً؛ لا يُستبدل تلقائياً.
      final primary = await customers.findByIdentifier('737111222');
      expect((primary as Success<Customer?>).value?.id, id);
    });

    test('fails gsm_conflict when phone belongs to another customer', () async {
      final a = await service.create(
        displayName: 'أ',
        identifierType: CustomerIdentifierType.username,
        identifierValue: 'user-a',
      );
      final b = await service.create(
        displayName: 'ب',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '738000111',
      );
      expect(a, isA<Success<Customer>>());
      expect(b, isA<Success<Customer>>());

      final r = await service.bindPrimaryGsm(
        customerId: (a as Success<Customer>).value.id,
        phone: '738000111',
      );
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'gsm_conflict');
    });

    test('fails when customer not active', () async {
      final created = await service.create(
        displayName: 'مؤقت ربط',
        identifierType: CustomerIdentifierType.username,
        identifierValue: 'prov-bind',
        status: CustomerStatus.provisional,
      );
      final id = (created as Success<Customer>).value.id;

      final r = await service.bindPrimaryGsm(
        customerId: id,
        phone: '739000111',
      );
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'customer_not_active');
    });

    test('fails when customer missing', () async {
      final r = await service.bindPrimaryGsm(
        customerId: 'ghost',
        phone: '739111222',
      );
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'customer_not_found');
    });
  });
}
