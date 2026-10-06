import 'package:drift/drift.dart';

import '../../core/result.dart';
import '../../domain/entities/broadcast.dart';
import '../database/app_database.dart';

/// مفتاح التنسيق القديم. لم يعد مصدرًا وقت التشغيل: يُقرأ مرة واحدة في ترحيل
/// `AppDatabase` إلى الجداول المسمّاة، ويبقى في الإعدادات كمسار رجوع فقط.
const broadcastJobsSettingKey = 'broadcast_jobs';

/// مستودع مهام البث على جداول Drift المسمّاة (broadcast_jobs /
/// broadcast_recipients) — مصدر الحقيقة الوحيد وقت التشغيل. لا قراءة ولا
/// كتابة لأي JSON إعدادات هنا.
final class LocalBroadcastRepository {
  const LocalBroadcastRepository({required this.database});

  final AppDatabase database;

  Future<Result<List<BroadcastJob>>> listAll() async {
    try {
      final rows = await (database.select(database.broadcastJobs)
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .get();
      final jobs = <BroadcastJob>[];
      for (final row in rows) {
        jobs.add(await _toJob(row));
      }
      return Success(jobs);
    } catch (error) {
      return Failure(
        AppFailure(code: 'broadcast_list_failed', message: error.toString()),
      );
    }
  }

  Future<Result<BroadcastJob?>> findById(String id) async {
    try {
      final row = await (database.select(database.broadcastJobs)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return const Success(null);
      return Success(await _toJob(row));
    } catch (error) {
      return Failure(
        AppFailure(code: 'broadcast_find_failed', message: error.toString()),
      );
    }
  }

  Future<Result<BroadcastJob?>> findByFingerprint(String fingerprint) async {
    try {
      final row = await (database.select(database.broadcastJobs)
            ..where((table) => table.fingerprint.equals(fingerprint))
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return const Success(null);
      return Success(await _toJob(row));
    } catch (error) {
      return Failure(
        AppFailure(code: 'broadcast_find_failed', message: error.toString()),
      );
    }
  }

  /// يحفظ المهمة ومستلميها معًا: صف المهمة يُحدَّث/يُدرج، ومستلموها يُستبدلون
  /// كاملين داخل معاملة واحدة حتى لا يبقى مستلم قديم أو ترتيب ناقص.
  Future<Result<void>> save(BroadcastJob job) async {
    try {
      await database.transaction(() async {
        await database.into(database.broadcastJobs).insertOnConflictUpdate(
              BroadcastJobsCompanion.insert(
                id: job.id,
                body: job.body,
                status: job.status.name,
                createdAt: job.createdAt,
                confirmedAt: Value(job.confirmedAt),
                completedAt: Value(job.completedAt),
                fingerprint: Value(job.fingerprint),
              ),
            );
        await (database.delete(database.broadcastRecipients)
              ..where((table) => table.jobId.equals(job.id)))
            .go();
        for (var index = 0; index < job.recipients.length; index++) {
          final recipient = job.recipients[index];
          await database.into(database.broadcastRecipients).insert(
                BroadcastRecipientsCompanion.insert(
                  jobId: job.id,
                  customerId: recipient.customerId,
                  position: Value(index),
                  phone: recipient.phone,
                  displayName: recipient.displayName,
                  status: recipient.status.name,
                  errorCode: Value(recipient.errorCode),
                  attempts: Value(recipient.attempts),
                  sentAt: Value(recipient.sentAt),
                ),
              );
        }
      });
      return const Success(null);
    } catch (error) {
      return Failure(
        AppFailure(code: 'broadcast_save_failed', message: error.toString()),
      );
    }
  }

  Future<BroadcastJob> _toJob(BroadcastJobRow row) async {
    final recipients = await (database.select(database.broadcastRecipients)
          ..where((table) => table.jobId.equals(row.id))
          ..orderBy([(table) => OrderingTerm(expression: table.position)]))
        .get();
    return BroadcastJob(
      id: row.id,
      body: row.body,
      status: _statusOf(row.status),
      createdAt: row.createdAt,
      confirmedAt: row.confirmedAt,
      completedAt: row.completedAt,
      fingerprint: row.fingerprint,
      recipients: [
        for (final recipient in recipients)
          BroadcastRecipient(
            customerId: recipient.customerId,
            phone: recipient.phone,
            displayName: recipient.displayName,
            status: _recipientStatusOf(recipient.status),
            errorCode: recipient.errorCode,
            attempts: recipient.attempts,
            sentAt: recipient.sentAt,
          ),
      ],
    );
  }

  BroadcastJobStatus _statusOf(String value) {
    for (final status in BroadcastJobStatus.values) {
      if (status.name == value) return status;
    }
    return BroadcastJobStatus.draft;
  }

  BroadcastRecipientStatus _recipientStatusOf(String value) {
    for (final status in BroadcastRecipientStatus.values) {
      if (status.name == value) return status;
    }
    return BroadcastRecipientStatus.pending;
  }
}
