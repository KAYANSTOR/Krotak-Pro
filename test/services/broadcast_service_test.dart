import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_broadcast_repository.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/broadcast.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/services/local_broadcast_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/services.dart';

final class _RecordingSender implements MessageSender {
  final sent = <(String, String)>[];
  final Set<String> failFor;

  _RecordingSender({Set<String>? failFor}) : failFor = failFor ?? <String>{};

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    if (failFor.contains(destination)) {
      return const Failure(AppFailure(code: 'sms_send_failed', message: 'denied'));
    }
    sent.add((destination, body));
    return const Success(null);
  }
}

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalSettingsRepository settings;
  late LocalAuditLogRepository auditLogs;
  late LocalCustomerService customerService;
  late LocalBroadcastService broadcast;
  late _RecordingSender sender;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    settings = LocalSettingsRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: DriftUnitOfWork(database),
      clock: FixedClock(DateTime(2026, 9, 13)),
      ids: SequentialIdGenerator(),
    );
    sender = _RecordingSender();
    broadcast = LocalBroadcastService(
      customers: customers,
      jobs: LocalBroadcastRepository(settings: settings),
      settings: settings,
      auditLogs: auditLogs,
      messageSender: sender,
      clock: FixedClock(DateTime(2026, 9, 13)),
      ids: SequentialIdGenerator(start: 100),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> addCustomer(String name, String phone) async {
    final result = await customerService.create(
      displayName: name,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    expect(result, isA<Success<Customer>>());
    return (result as Success<Customer>).value;
  }

  test('preview excludes blacklisted and invalid phones', () async {
    await addCustomer('علي', '0777123456');
    final blocked = await addCustomer('محظور', '0777000000');
    await customerService.blacklist(blocked.id);
    await customerService.create(
      displayName: 'بدون رقم صالح',
      identifierType: CustomerIdentifierType.username,
      identifierValue: 'user-1',
    );

    final preview = await broadcast.preview(body: 'عرض اليوم');
    expect(preview, isA<Success<BroadcastPreview>>());
    final value = (preview as Success<BroadcastPreview>).value;
    expect(value.eligibleCount, 1);
    expect(value.eligible.single.phone, '777123456');
    expect(value.excludedBlacklisted, 1);
    expect(value.excludedInvalidPhone, 1);
  });

  test('refuses send without explicit confirmation phrase', () async {
    await addCustomer('علي', '0777123456');
    final result = await broadcast.confirm(body: 'مرحبا', confirmationPhrase: 'نعم');
    expect(result, isA<Failure<BroadcastJob>>());
    expect((result as Failure<BroadcastJob>).error.code, 'broadcast_confirmation_required');
    expect(sender.sent, isEmpty);
  });

  test('sends to eligible recipients and records audit', () async {
    await addCustomer('علي', '0777123456');
    await addCustomer('فاطمة', '+967777654321');

    final confirmed = await broadcast.confirm(body: 'صيانة الليلة', confirmationPhrase: 'إرسال');
    expect(confirmed, isA<Success<BroadcastJob>>());
    final job = (confirmed as Success<BroadcastJob>).value;
    expect(job.total, 2);

    final ran = await broadcast.run(job.id);
    expect(ran, isA<Success<BroadcastJob>>());
    final done = (ran as Success<BroadcastJob>).value;
    expect(done.status, BroadcastJobStatus.completed);
    expect(done.sentCount, 2);
    expect(sender.sent.map((e) => e.$1), containsAll(['777123456', '777654321']));

    final logs = await auditLogs.findByEntity('broadcast', job.id);
    expect((logs as Success).value, isNotEmpty);
  });

  test('does not create a second job for the same body and recipients', () async {
    await addCustomer('علي', '0777123456');
    final first = await broadcast.confirm(body: 'نفس النص', confirmationPhrase: 'إرسال');
    final second = await broadcast.confirm(body: 'نفس النص', confirmationPhrase: 'إرسال');
    expect((first as Success<BroadcastJob>).value.id, (second as Success<BroadcastJob>).value.id);
  });

  test('marks partial failure when some numbers reject send', () async {
    await addCustomer('علي', '0777123456');
    await addCustomer('فاشل', '0777111111');
    sender.failFor.add('777111111');

    final confirmed = await broadcast.confirm(body: 'تنبيه', confirmationPhrase: 'إرسال');
    final job = (confirmed as Success<BroadcastJob>).value;
    final ran = await broadcast.run(job.id);
    final done = (ran as Success<BroadcastJob>).value;
    expect(done.status, BroadcastJobStatus.partiallyFailed);
    expect(done.sentCount, 1);
    expect(done.failedCount, 1);
  });
}
