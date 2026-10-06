import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide AppSetting, Customer, Transaction;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_broadcast_repository.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/broadcast.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/services/local_backup_service.dart';
import 'package:net_app/domain/services/local_broadcast_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/domain/services/services.dart';

final class _RecordingSender implements MessageSender {
  final sent = <(String, String)>[];
  final Set<String> failFor;

  _RecordingSender({Set<String>? failFor}) : failFor = failFor ?? <String>{};

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    if (failFor.contains(destination)) {
      return const Failure(
        AppFailure(code: 'sms_send_failed', message: 'denied'),
      );
    }
    sent.add((destination, body));
    return const Success(null);
  }
}

/// البث: بعد الترحيل إلى جداول Drift المسمّاة — الاستمرار بعد إعادة التشغيل،
/// استئناف مهمة ناقصة بلا تكرار، ونجاة المهام من نسخة احتياطية/استعادة.
void main() {
  late Directory workDir;
  late File dbFile;
  late AppDatabase database;

  setUp(() async {
    workDir = Directory.systemTemp.createTempSync('krotak-broadcast-store');
    dbFile = File(p.join(workDir.path, 'net.sqlite'));
    database = AppDatabase(NativeDatabase(dbFile));
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
  });

  Future<LocalBroadcastService> serviceFor(
    AppDatabase db,
    _RecordingSender sender,
  ) async {
    final customers = LocalCustomerRepository(db);
    final settings = LocalSettingsRepository(db);
    final auditLogs = LocalAuditLogRepository(db);
    final clock = FixedClock(DateTime(2026, 9, 13, 10));
    final customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: DriftUnitOfWork(db),
      clock: clock,
      ids: SequentialIdGenerator(),
    );
    for (final entry in const {
      '733000001': 'المستلم الأول',
      '733000002': 'المستلم الثاني',
      '733000003': 'المستلم الثالث',
    }.entries) {
      await customerService.create(
        displayName: entry.value,
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: entry.key,
      );
    }
    return LocalBroadcastService(
      customers: customers,
      jobs: LocalBroadcastRepository(database: db),
      settings: settings,
      auditLogs: auditLogs,
      messageSender: sender,
      clock: clock,
      ids: SequentialIdGenerator(start: 100),
      transactions: LocalTransactionRepository(db),
      posRegistry: LocalPosAccountRegistry(settings: settings, clock: clock),
    );
  }

  test('a running broadcast survives a restart and resumes without duplicates',
      () async {
    final firstRunSender = _RecordingSender(failFor: {'733000002'});
    final first = await serviceFor(database, firstRunSender);
    final confirmed = await first.confirm(
      body: 'رسالة جماعية للاختبار',
      confirmationPhrase: LocalBroadcastService.requiredConfirmation,
    );
    expect(confirmed, isA<Success<BroadcastJob>>());
    final confirmedJob = (confirmed as Success<BroadcastJob>).value;
    final jobId = confirmedJob.id;
    final originalOrder =
        confirmedJob.recipients.map((r) => r.phone).toList(growable: false);

    final ran = await first.run(jobId);
    expect(ran, isA<Success<BroadcastJob>>());
    final afterRun = (ran as Success<BroadcastJob>).value;
    // الفاشل واحد فقط، فلا تكتمل المهمة ولا تفشل كاملة.
    expect(afterRun.status, BroadcastJobStatus.partiallyFailed);
    expect(afterRun.sentCount, 2);
    expect(afterRun.failedCount, 1);
    expect(firstRunSender.sent, hasLength(2));

    // إغلاق القاعدة وإعادة فتحها = إعادة تشغيل التطبيق.
    await database.close();
    database = AppDatabase(NativeDatabase(dbFile));

    final resumedSender = _RecordingSender();
    final resumed = await serviceFor(database, resumedSender);
    final listed = await resumed.listJobs();
    expect(listed, isA<Success<List<BroadcastJob>>>());
    final job = (listed as Success<List<BroadcastJob>>).value.single;
    expect(job.id, jobId);
    expect(job.body, 'رسالة جماعية للاختبار');
    // الترتيب نفسه وكل حالة مع مستلمها الصحيح بعد إعادة التشغيل.
    expect(job.recipients.map((r) => r.phone), originalOrder);
    final states = {for (final r in job.recipients) r.phone: r.status};
    expect(states['733000002'], BroadcastRecipientStatus.failed);
    expect(states['733000001'], BroadcastRecipientStatus.sent);
    expect(states['733000003'], BroadcastRecipientStatus.sent);
    expect(
      job.recipients.firstWhere((r) => r.phone == '733000002').errorCode,
      'sms_send_failed',
    );

    // مهمة انتهت جزئيًا حالة نهائية: لا يعاد إرسال أي مستلم عند إعادة التشغيل.
    final again = await resumed.run(jobId);
    expect(again, isA<Success<BroadcastJob>>());
    expect(
      (again as Success<BroadcastJob>).value.status,
      BroadcastJobStatus.partiallyFailed,
    );
    expect(resumedSender.sent, isEmpty, reason: 'لا تكرار إرسال لمهمة انتهت');

    // أما مهمة قُطع تشغيلها وهي `running` فتُستانف: المرسل يُتخطى والمنتظر يُرسل.
    final stuck = await LocalBroadcastRepository(database: database).save(
      BroadcastJob(
        id: 'bcast-stuck',
        body: 'رسالة قُطعت',
        status: BroadcastJobStatus.running,
        createdAt: DateTime(2026, 9, 13, 9, 30),
        fingerprint: 'fp-stuck',
        recipients: const [
          BroadcastRecipient(
            customerId: 'c-done',
            phone: '733000001',
            displayName: 'أُرسل سابقًا',
            status: BroadcastRecipientStatus.sent,
          ),
          BroadcastRecipient(
            customerId: 'c-waiting',
            phone: '733000003',
            displayName: 'بانتظار الإرسال',
            status: BroadcastRecipientStatus.pending,
          ),
        ],
      ),
    );
    expect(stuck, isA<Success<void>>());
    final resumedRun = await resumed.run('bcast-stuck');
    expect(resumedRun, isA<Success<BroadcastJob>>());
    final finished = (resumedRun as Success<BroadcastJob>).value;
    expect(resumedSender.sent.map((e) => e.$1), ['733000003']);
    expect(finished.status, BroadcastJobStatus.completed);
    expect(finished.sentCount, 2);
    expect(finished.total, 2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('broadcast jobs survive a real backup/restore of the database', () async {
    final sender = _RecordingSender();
    final service = await serviceFor(database, sender);
    final confirmed = await service.confirm(
      body: 'رسالة قبل النسخة الاحتياطية',
      confirmationPhrase: LocalBroadcastService.requiredConfirmation,
    );
    final confirmedJob = (confirmed as Success<BroadcastJob>).value;
    final jobId = confirmedJob.id;
    final originalOrder =
        confirmedJob.recipients.map((r) => r.phone).toList(growable: false);
    await service.run(jobId);
    await database.close();

    final settings = LocalSettingsRepository(database);
    final backup = LocalBackupService(
      settings: settings,
      clock: FixedClock(DateTime(2026, 9, 13, 11)),
      ids: SequentialIdGenerator(start: 500),
      backupDirectory: Directory(p.join(workDir.path, 'backups')),
      databaseFile: dbFile,
    );
    final created = await backup.createBackup(password: 'pass123', label: 'test');
    expect(created, isA<Success<File>>());
    final backupFile = (created as Success<File>).value;
    expect(await backupFile.exists(), isTrue);

    // فقدان القاعدة الفعلي ثم استعادتها من النسخة.
    await dbFile.delete();
    final restored = await backup.restoreFromFile(
      backupFile,
      password: 'pass123',
      closeDatabase: () async {},
    );
    expect(restored, isA<Success<BackupRestoreReport>>());
    expect((restored as Success<BackupRestoreReport>).value.databaseRestored, isTrue);

    database = AppDatabase(NativeDatabase(dbFile));
    final jobs = await LocalBroadcastRepository(database: database).listAll();
    expect(jobs, isA<Success<List<BroadcastJob>>>());
    final job = (jobs as Success<List<BroadcastJob>>).value.single;
    expect(job.id, jobId);
    expect(job.status, BroadcastJobStatus.completed);
    expect(job.recipients.map((r) => r.phone), originalOrder);
    expect(
      job.recipients.map((r) => r.status),
      everyElement(BroadcastRecipientStatus.sent),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('legacy JSON rows keep their order and are not duplicated on reopen',
      () async {
    final repo = LocalBroadcastRepository(database: database);
    await repo.save(
      BroadcastJob(
        id: 'bcast-order',
        body: 'نص',
        status: BroadcastJobStatus.confirmed,
        createdAt: DateTime.utc(2026, 9, 13, 9),
        confirmedAt: DateTime.utc(2026, 9, 13, 9),
        fingerprint: 'fp-order',
        recipients: const [
          BroadcastRecipient(
            customerId: 'c-3',
            phone: '733000003',
            displayName: 'الثالث',
            status: BroadcastRecipientStatus.pending,
          ),
          BroadcastRecipient(
            customerId: 'c-1',
            phone: '733000001',
            displayName: 'الأول',
            status: BroadcastRecipientStatus.sent,
          ),
          BroadcastRecipient(
            customerId: 'c-2',
            phone: '733000002',
            displayName: 'الثاني',
            status: BroadcastRecipientStatus.failed,
            errorCode: 'sms_send_failed',
            attempts: 2,
          ),
        ],
      ),
    );
    // البحث بالفصمة يقرأ من الجداول لا من JSON الإعدادات.
    final byFingerprint = await repo.findByFingerprint('fp-order');
    expect(
      (byFingerprint as Success<BroadcastJob?>).value?.recipients.map((r) => r.phone),
      ['733000003', '733000001', '733000002'],
    );

    await database.close();
    database = AppDatabase(NativeDatabase(dbFile));
    final reread = await LocalBroadcastRepository(database: database).findById('bcast-order');
    final job = (reread as Success<BroadcastJob?>).value!;
    expect(job.recipients.map((r) => r.customerId), ['c-3', 'c-1', 'c-2']);
    expect(job.recipients[2].attempts, 2);
    expect(job.recipients[2].errorCode, 'sms_send_failed');
    expect(job.recipients[1].status, BroadcastRecipientStatus.sent);

    // ولا صف JSON قديم في الإعدادات لهذه المهمة (مصدر واحد فقط).
    final legacy = await LocalSettingsRepository(database).find(
      broadcastJobsSettingKey,
    );
    expect((legacy as Success<AppSetting?>).value, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
