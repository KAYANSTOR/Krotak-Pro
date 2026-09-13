import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';
import 'message_retry_policy.dart';

final class MessageRetryState {
  const MessageRetryState({
    required this.attempts,
    required this.nextRetryAt,
    this.lastErrorCode,
    this.exhausted = false,
    this.immediateRequested = false,
  });

  final int attempts;
  final DateTime? nextRetryAt;
  final String? lastErrorCode;
  final bool exhausted;
  final bool immediateRequested;
}

final class LocalMessageRetryService {
  const LocalMessageRetryService({
    required this.auditLogs,
    required this.messages,
    required this.clock,
    required this.ids,
    this.policy = const MessageRetryPolicy(),
  });

  final AuditLogRepository auditLogs;
  final MessageRepository messages;
  final Clock clock;
  final IdGenerator ids;
  final MessageRetryPolicy policy;

  Future<Result<MessageRetryState>> state(String messageId) async {
    final result = await auditLogs.findByEntity('message', messageId);
    if (result is Failure<List<AuditLog>>) return Failure(result.error);
    final logs = List<AuditLog>.of((result as Success<List<AuditLog>>).value)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    var attempts = 0;
    DateTime? nextRetryAt;
    String? lastErrorCode;
    var exhausted = false;
    var immediateRequested = false;
    for (final log in logs) {
      switch (log.action) {
        case 'message_retry_scheduled':
          final payload = _decode(log.payloadJson);
          attempts = int.tryParse('${payload['attempt'] ?? attempts}') ?? attempts;
          final rawNext = payload['nextRetryAt']?.toString();
          nextRetryAt = rawNext == null ? nextRetryAt : DateTime.tryParse(rawNext);
          lastErrorCode = payload['errorCode']?.toString() ?? lastErrorCode;
          immediateRequested = false;
          exhausted = false;
        case 'message_retry_requested':
          immediateRequested = true;
          exhausted = false;
          nextRetryAt = null;
        case 'message_retry_cleared':
          attempts = 0;
          nextRetryAt = null;
          lastErrorCode = null;
          exhausted = false;
          immediateRequested = false;
        case 'message_retry_exhausted':
          exhausted = true;
          nextRetryAt = null;
          final payload = _decode(log.payloadJson);
          attempts = int.tryParse('${payload['attempts'] ?? attempts}') ?? attempts;
          lastErrorCode = payload['errorCode']?.toString() ?? lastErrorCode;
      }
    }
    return Success(MessageRetryState(
      attempts: attempts,
      nextRetryAt: nextRetryAt,
      lastErrorCode: lastErrorCode,
      exhausted: exhausted,
      immediateRequested: immediateRequested,
    ));
  }

  Future<Result<MessageRetryState>> recordFailure({required String messageId, required AppFailure error}) async {
    if (!policy.isRetryableCode(error.code)) {
      return Success(MessageRetryState(attempts: 0, nextRetryAt: null, lastErrorCode: error.code, exhausted: true));
    }
    final current = await state(messageId);
    if (current is Failure<MessageRetryState>) return Failure(current.error);
    final previous = (current as Success<MessageRetryState>).value;
    if (!policy.canRetry(previous.attempts)) {
      final audit = await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'message',
        entityId: messageId,
        action: 'message_retry_exhausted',
        occurredAt: clock.now(),
        payloadJson: jsonEncode({'attempts': previous.attempts, 'errorCode': error.code}),
      ));
      if (audit is Failure<void>) return Failure(audit.error);
      await messages.updateStatus(messageId, MessageProcessingStatus.failed);
      return Success(MessageRetryState(attempts: previous.attempts, nextRetryAt: null, lastErrorCode: error.code, exhausted: true));
    }
    final attempt = previous.attempts + 1;
    final next = clock.now().add(policy.delayForAttempt(attempt));
    final audit = await auditLogs.append(AuditLog(
      id: ids.next('audit'),
      entityType: 'message',
      entityId: messageId,
      action: 'message_retry_scheduled',
      occurredAt: clock.now(),
      payloadJson: jsonEncode({'attempt': attempt, 'nextRetryAt': next.toIso8601String(), 'errorCode': error.code}),
    ));
    if (audit is Failure<void>) return Failure(audit.error);
    final status = await messages.updateStatus(messageId, MessageProcessingStatus.failed);
    if (status is Failure<void>) return Failure(status.error);
    return Success(MessageRetryState(attempts: attempt, nextRetryAt: next, lastErrorCode: error.code));
  }

  Future<Result<void>> clearAfterSuccess(String messageId) => auditLogs.append(AuditLog(
        id: ids.next('audit'), entityType: 'message', entityId: messageId,
        action: 'message_retry_cleared', occurredAt: clock.now(),
      ));

  Future<Result<void>> requestImmediateRetry(String messageId) => auditLogs.append(AuditLog(
        id: ids.next('audit'), entityType: 'message', entityId: messageId,
        action: 'message_retry_requested', occurredAt: clock.now(),
      ));

  Future<bool> isDue(String messageId, {DateTime? now}) async {
    final result = await state(messageId);
    if (result is Failure<MessageRetryState>) return false;
    final s = (result as Success<MessageRetryState>).value;
    if (s.immediateRequested) return true;
    if (s.exhausted) return false;
    return s.nextRetryAt == null || !s.nextRetryAt!.isAfter(now ?? clock.now());
  }

  Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }
}
