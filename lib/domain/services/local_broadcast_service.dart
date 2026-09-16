import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/broadcast.dart';
import '../entities/customer.dart';
import '../entities/setting.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import '../../data/repositories/local_broadcast_repository.dart';
import 'services.dart';

final class LocalBroadcastService implements BroadcastService {
  LocalBroadcastService({
    required this.customers,
    required this.jobs,
    required this.settings,
    required this.auditLogs,
    required this.messageSender,
    required this.clock,
    required this.ids,
    this.sendDelay = Duration.zero,
  });

  final CustomerRepository customers;
  final LocalBroadcastRepository jobs;
  final SettingsRepository settings;
  final AuditLogRepository auditLogs;
  final MessageSender messageSender;
  final Clock clock;
  final IdGenerator ids;
  final Duration sendDelay;

  static const requiredConfirmation = 'إرسال';

  @override
  Future<Result<BroadcastPreview>> preview({required String body}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const Failure(AppFailure(code: 'broadcast_empty_body', message: 'نص الرسالة فارغ'));
    }
    final classified = await _classifyRecipients();
    if (classified is Failure<_ClassifiedRecipients>) return Failure(classified.error);
    final bag = (classified as Success<_ClassifiedRecipients>).value;
    return Success(
      BroadcastPreview(
        body: trimmed,
        eligible: bag.eligible,
        excludedBlacklisted: bag.blacklisted,
        excludedInvalidPhone: bag.invalidPhone,
        excludedInactive: bag.inactive,
      ),
    );
  }

  @override
  Future<Result<BroadcastJob>> confirm({
    required String body,
    required String confirmationPhrase,
  }) async {
    if (confirmationPhrase.trim() != requiredConfirmation) {
      return const Failure(
        AppFailure(code: 'broadcast_confirmation_required', message: 'يجب كتابة كلمة إرسال للتأكيد'),
      );
    }
    final previewResult = await preview(body: body);
    if (previewResult is Failure<BroadcastPreview>) return Failure(previewResult.error);
    final previewValue = (previewResult as Success<BroadcastPreview>).value;
    if (previewValue.eligible.isEmpty) {
      return const Failure(AppFailure(code: 'broadcast_no_recipients', message: 'لا يوجد مستلمون مؤهلون'));
    }

    final fingerprint = _fingerprint(previewValue.body, previewValue.eligible.map((e) => e.phone));
    final existing = await jobs.findByFingerprint(fingerprint);
    if (existing is Failure<BroadcastJob?>) return Failure(existing.error);
    final existingJob = (existing as Success<BroadcastJob?>).value;
    if (existingJob != null &&
        existingJob.status != BroadcastJobStatus.cancelled &&
        existingJob.status != BroadcastJobStatus.failed) {
      return Success(existingJob);
    }

    final now = clock.now();
    final job = BroadcastJob(
      id: ids.next('bcast'),
      body: previewValue.body,
      status: BroadcastJobStatus.confirmed,
      createdAt: now,
      confirmedAt: now,
      fingerprint: fingerprint,
      recipients: previewValue.eligible,
    );
    final saved = await jobs.save(job);
    if (saved is Failure<void>) return Failure(saved.error);
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'broadcast',
        entityId: job.id,
        action: 'confirmed',
        occurredAt: now,
        payloadJson: jsonEncode({'recipients': job.total}),
      ),
    );
    return Success(job);
  }

  @override
  Future<Result<BroadcastJob>> run(
    String jobId, {
    void Function(BroadcastProgress progress)? onProgress,
  }) async {
    final found = await jobs.findById(jobId);
    if (found is Failure<BroadcastJob?>) return Failure(found.error);
    final foundJob = (found as Success<BroadcastJob?>).value;
    if (foundJob == null) {
      return const Failure(AppFailure(code: 'broadcast_not_found', message: 'المهمة غير موجودة'));
    }
    if (foundJob.status == BroadcastJobStatus.cancelled) {
      return const Failure(AppFailure(code: 'broadcast_cancelled', message: 'المهمة ملغاة'));
    }
    if (foundJob.status == BroadcastJobStatus.completed || foundJob.status == BroadcastJobStatus.partiallyFailed) {
      return Success(foundJob);
    }

    var job = foundJob.copyWith(status: BroadcastJobStatus.running);
    await jobs.save(job);
    onProgress?.call(BroadcastProgress(jobId: job.id, done: job.sentCount + job.failedCount + job.skippedCount, total: job.total, status: job.status));

    final maxAttempts = await _intSetting(SettingKeys.broadcastMaxAttempts, SettingDefaults.broadcastMaxAttempts);
    final updated = [...job.recipients];

    for (var i = 0; i < updated.length; i++) {
      final latest = await jobs.findById(job.id);
      if (latest is Success<BroadcastJob?> && latest.value?.status == BroadcastJobStatus.paused) {
        return Success(latest.value!);
      }
      if (latest is Success<BroadcastJob?> && latest.value?.status == BroadcastJobStatus.cancelled) {
        return Success(latest.value!);
      }

      var recipient = updated[i];
      if (recipient.status == BroadcastRecipientStatus.sent || recipient.status == BroadcastRecipientStatus.skipped) {
        continue;
      }
      if (recipient.attempts >= maxAttempts && recipient.status == BroadcastRecipientStatus.failed) {
        continue;
      }

      if (sendDelay > Duration.zero) {
        await Future<void>.delayed(sendDelay);
      }

      final send = await messageSender.send(destination: recipient.phone, body: job.body);
      if (send is Success<void>) {
        updated[i] = recipient.copyWith(
          status: BroadcastRecipientStatus.sent,
          attempts: recipient.attempts + 1,
          sentAt: clock.now(),
          clearError: true,
        );
      } else {
        final failure = send as Failure<void>;
        updated[i] = recipient.copyWith(
          status: BroadcastRecipientStatus.failed,
          attempts: recipient.attempts + 1,
          errorCode: failure.error.code,
        );
      }

      job = job.copyWith(recipients: updated, status: BroadcastJobStatus.running);
      await jobs.save(job);
      onProgress?.call(
        BroadcastProgress(
          jobId: job.id,
          done: job.sentCount + job.failedCount + job.skippedCount,
          total: job.total,
          status: job.status,
        ),
      );
    }

    final terminal = job.failedCount == 0
        ? BroadcastJobStatus.completed
        : (job.sentCount == 0 ? BroadcastJobStatus.failed : BroadcastJobStatus.partiallyFailed);
    job = job.copyWith(status: terminal, completedAt: clock.now(), recipients: updated);
    await jobs.save(job);
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'broadcast',
        entityId: job.id,
        action: terminal.name,
        occurredAt: clock.now(),
        payloadJson: jsonEncode({'sent': job.sentCount, 'failed': job.failedCount, 'skipped': job.skippedCount}),
      ),
    );
    onProgress?.call(BroadcastProgress(jobId: job.id, done: job.total, total: job.total, status: job.status));
    return Success(job);
  }

  @override
  Future<Result<BroadcastJob>> pause(String jobId) => _setStatus(jobId, BroadcastJobStatus.paused);

  @override
  Future<Result<BroadcastJob>> cancel(String jobId) => _setStatus(jobId, BroadcastJobStatus.cancelled);

  @override
  Future<Result<List<BroadcastJob>>> listJobs() => jobs.listAll();

  Future<Result<BroadcastJob>> _setStatus(String jobId, BroadcastJobStatus status) async {
    final found = await jobs.findById(jobId);
    if (found is Failure<BroadcastJob?>) return Failure(found.error);
    final job = (found as Success<BroadcastJob?>).value;
    if (job == null) {
      return const Failure(AppFailure(code: 'broadcast_not_found', message: 'المهمة غير موجودة'));
    }
    final next = job.copyWith(status: status);
    final saved = await jobs.save(next);
    if (saved is Failure<void>) return Failure(saved.error);
    return Success(next);
  }

  Future<Result<_ClassifiedRecipients>> _classifyRecipients() async {
    final listed = await customers.search('');
    if (listed is Failure<List<Customer>>) return Failure(listed.error);
    final eligible = <BroadcastRecipient>[];
    var blacklisted = 0;
    var invalidPhone = 0;
    var inactive = 0;
    final seenPhones = <String>{};

    for (final customer in (listed as Success<List<Customer>>).value) {
      if (customer.status == CustomerStatus.blacklisted) {
        blacklisted++;
        continue;
      }
      if (customer.status != CustomerStatus.active) {
        inactive++;
        continue;
      }
      final idsResult = await customers.listIdentifiers(customer.id);
      if (idsResult is Failure<List<CustomerIdentifier>>) return Failure(idsResult.error);
      final phones = (idsResult as Success<List<CustomerIdentifier>>).value.where(
        (row) => row.type == CustomerIdentifierType.phoneNumber,
      );
      if (phones.isEmpty) {
        invalidPhone++;
        continue;
      }
      final primary = phones.firstWhere((row) => row.isPrimary, orElse: () => phones.first);
      final canonical = PhoneNormalizer.canonicalize(primary.value);
      if (canonical == null) {
        invalidPhone++;
        continue;
      }
      if (!seenPhones.add(canonical)) {
        continue;
      }
      eligible.add(
        BroadcastRecipient(
          customerId: customer.id,
          phone: canonical,
          displayName: customer.displayName,
          status: BroadcastRecipientStatus.pending,
        ),
      );
    }
    return Success(
      _ClassifiedRecipients(
        eligible: eligible,
        blacklisted: blacklisted,
        invalidPhone: invalidPhone,
        inactive: inactive,
      ),
    );
  }

  String _fingerprint(String body, Iterable<String> phones) {
    final joined = [...phones]..sort();
    return '${body.hashCode}:${joined.join(',')}';
  }

  Future<int> _intSetting(String key, int fallback) async {
    final raw = await settings.find(key);
    if (raw is! Success<AppSetting?>) return fallback;
    return int.tryParse(raw.value?.value ?? '') ?? fallback;
  }
}

final class _ClassifiedRecipients {
  const _ClassifiedRecipients({
    required this.eligible,
    required this.blacklisted,
    required this.invalidPhone,
    required this.inactive,
  });

  final List<BroadcastRecipient> eligible;
  final int blacklisted;
  final int invalidPhone;
  final int inactive;
}
