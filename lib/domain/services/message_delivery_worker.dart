import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';
import 'local_message_retry_service.dart';
import 'message_retry_policy.dart';
import 'services.dart';

/// Phase 4 delivery worker: resend voucher SMS for already-committed sales.
///
/// Rules (screenshots + Phase 3):
/// - Only messages with `voucher_committed` and without `sms_delivery_succeeded`
/// - Never issues a second card; uses the same cardId from the audit payload
/// - Respects [MessageRetryPolicy] (max 3 attempts, exponential backoff)
/// - Stuck `sending` / `pending` older than [MessageRetryPolicy.confirmPendingTimeout]
///   (15 minutes) are treated as due for another delivery attempt
final class MessageDeliveryWorker {
  const MessageDeliveryWorker({
    required this.messages,
    required this.auditLogs,
    required this.cards,
    required this.messageSender,
    required this.retryService,
    required this.clock,
    required this.ids,
    this.policy = const MessageRetryPolicy(),
  });

  final MessageRepository messages;
  final AuditLogRepository auditLogs;
  final CardRepository cards;
  final MessageSender messageSender;
  final MessageRetryServicePort retryService;
  final Clock clock;
  final IdGenerator ids;
  final MessageRetryPolicy policy;

  /// Single worker tick. Safe to call on resume / periodic timer.
  Future<Result<DeliveryWorkerReport>> tick() async {
    final candidates = await _candidateMessages();
    if (candidates is Failure<List<IncomingMessage>>) {
      return Failure(candidates.error);
    }

    var attempted = 0;
    var delivered = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (final message in (candidates as Success<List<IncomingMessage>>).value) {
      final commit = await _findVoucherCommit(message.id);
      if (commit is Failure<_VoucherCommit?>) {
        failed++;
        errors.add('${message.id}:${commit.error.code}');
        continue;
      }
      final voucher = (commit as Success<_VoucherCommit?>).value;
      if (voucher == null) {
        skipped++;
        continue;
      }

      final alreadySent = await _hasSmsSuccess(message.id);
      if (alreadySent is Failure<bool>) {
        failed++;
        errors.add('${message.id}:${alreadySent.error.code}');
        continue;
      }
      if ((alreadySent as Success<bool>).value) {
        if (message.status != MessageProcessingStatus.processed) {
          await messages.updateStatus(message.id, MessageProcessingStatus.processed);
        }
        await retryService.clearAfterSuccess(message.id);
        skipped++;
        continue;
      }

      final due = await _isDeliveryDue(message, voucher);
      if (due is Failure<bool>) {
        failed++;
        errors.add('${message.id}:${due.error.code}');
        continue;
      }
      if (!(due as Success<bool>).value) {
        skipped++;
        continue;
      }

      attempted++;
      final cardResult = await cards.findById(voucher.cardId);
      if (cardResult is Failure<Card?>) {
        failed++;
        errors.add('${message.id}:${cardResult.error.code}');
        continue;
      }
      final card = (cardResult as Success<Card?>).value;
      if (card == null) {
        failed++;
        errors.add('${message.id}:card_not_found');
        await retryService.recordFailure(
          messageId: message.id,
          error: const AppFailure(code: 'card_not_found', message: 'Committed card missing'),
        );
        continue;
      }

      final body =
          'بطاقة الإنترنت\nالرقم: ${card.serialNumber}\nالرمز: ${card.secretCode}';
      final sent = await messageSender.send(
        destination: voucher.destination,
        body: body,
      );
      if (sent is Failure<void>) {
        await auditLogs.append(
          AuditLog(
            id: ids.next('audit'),
            entityType: 'message',
            entityId: message.id,
            action: 'sms_delivery_failed',
            occurredAt: clock.now(),
            payloadJson:
                '{"operationId":"${voucher.operationId}","cardId":"${voucher.cardId}","categoryId":"${voucher.categoryId}","reservationId":"${voucher.reservationId}","destination":"${voucher.destination}","error":"${sent.error.code}","source":"delivery_worker"}',
          ),
        );
        final scheduled = await retryService.recordFailure(
          messageId: message.id,
          error: sent.error.code.isEmpty
              ? const AppFailure(code: 'sms_delivery_failed', message: 'SMS send failed')
              : sent.error,
        );
        if (scheduled is Failure<MessageRetryState>) {
          failed++;
          errors.add('${message.id}:${scheduled.error.code}');
        } else {
          final state = (scheduled as Success<MessageRetryState>).value;
          if (state.exhausted) {
            failed++;
            errors.add('${message.id}:retry_exhausted:sms_delivery_failed');
          } else {
            skipped++;
          }
        }
        continue;
      }

      final audit = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: message.id,
          action: 'sms_delivery_succeeded',
          occurredAt: clock.now(),
          payloadJson:
              '{"operationId":"${voucher.operationId}","cardId":"${voucher.cardId}","categoryId":"${voucher.categoryId}","reservationId":"${voucher.reservationId}","destination":"${voucher.destination}","source":"delivery_worker"}',
        ),
      );
      if (audit is Failure<void>) {
        failed++;
        errors.add('${message.id}:${audit.error.code}');
        continue;
      }
      await messages.updateStatus(message.id, MessageProcessingStatus.processed);
      await retryService.clearAfterSuccess(message.id);
      delivered++;
    }

    return Success(
      DeliveryWorkerReport(
        attempted: attempted,
        delivered: delivered,
        skipped: skipped,
        failed: failed,
        errors: errors,
      ),
    );
  }

  Future<Result<List<IncomingMessage>>> _candidateMessages() async {
    final failed = await messages.listByStatus(MessageProcessingStatus.failed);
    if (failed is Failure<List<IncomingMessage>>) return Failure(failed.error);
    final sending = await messages.listByStatus(MessageProcessingStatus.sending);
    if (sending is Failure<List<IncomingMessage>>) return Failure(sending.error);
    final pending = await messages.listByStatus(MessageProcessingStatus.pending);
    if (pending is Failure<List<IncomingMessage>>) return Failure(pending.error);

    final map = <String, IncomingMessage>{};
    for (final m in (failed as Success<List<IncomingMessage>>).value) {
      map[m.id] = m;
    }
    for (final m in (sending as Success<List<IncomingMessage>>).value) {
      map[m.id] = m;
    }
    for (final m in (pending as Success<List<IncomingMessage>>).value) {
      map[m.id] = m;
    }
    final list = map.values.toList()
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return Success(list);
  }

  Future<Result<_VoucherCommit?>> _findVoucherCommit(String messageId) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return Failure(logs.error);
    final entries = (logs as Success<List<AuditLog>>)
        .value
        .where((l) => l.action == 'voucher_committed')
        .toList(growable: false);
    if (entries.isEmpty) return const Success(null);
    final payload = entries.last.payloadJson ?? '';
    final cardId = _field(payload, 'cardId');
    final reservationId = _field(payload, 'reservationId');
    final categoryId = _field(payload, 'categoryId');
    final destination = _field(payload, 'destination');
    final operationId = _field(payload, 'operationId') ?? '';
    if (cardId == null ||
        reservationId == null ||
        categoryId == null ||
        destination == null ||
        destination.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'delivery_state_invalid',
          message: 'voucher_committed payload is incomplete',
        ),
      );
    }
    final occurredAt = entries.last.occurredAt;
    return Success(
      _VoucherCommit(
        cardId: cardId,
        reservationId: reservationId,
        categoryId: categoryId,
        destination: destination,
        operationId: operationId,
        committedAt: occurredAt,
      ),
    );
  }

  Future<Result<bool>> _hasSmsSuccess(String messageId) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return Failure(logs.error);
    final ok = (logs as Success<List<AuditLog>>)
        .value
        .any((l) => l.action == 'sms_delivery_succeeded');
    return Success(ok);
  }

  Future<Result<bool>> _isDeliveryDue(IncomingMessage message, _VoucherCommit voucher) async {
    final retryDue = await retryService.isDue(message.id);
    if (retryDue) return const Success(true);

    final timedOut = policy.shouldRequeueAfterConfirmTimeout(
      status: message.status == MessageProcessingStatus.failed
          ? MessageProcessingStatus.sending
          : message.status,
      lastAttemptAt: voucher.committedAt,
      now: clock.now(),
    );
    if (timedOut) return const Success(true);

    final state = await retryService.state(message.id);
    if (state is Failure<MessageRetryState>) return Failure(state.error);
    final s = (state as Success<MessageRetryState>).value;
    if (message.status == MessageProcessingStatus.failed &&
        s.attempts == 0 &&
        !s.exhausted) {
      return const Success(true);
    }
    return const Success(false);
  }

  String? _field(String payload, String name) {
    final match = RegExp('"$name":"([^"]*)"').firstMatch(payload);
    return match?.group(1);
  }
}

final class _VoucherCommit {
  const _VoucherCommit({
    required this.cardId,
    required this.reservationId,
    required this.categoryId,
    required this.destination,
    required this.operationId,
    required this.committedAt,
  });

  final String cardId;
  final String reservationId;
  final String categoryId;
  final String destination;
  final String operationId;
  final DateTime committedAt;
}

final class DeliveryWorkerReport {
  const DeliveryWorkerReport({
    required this.attempted,
    required this.delivered,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int attempted;
  final int delivered;
  final int skipped;
  final int failed;
  final List<String> errors;
}
