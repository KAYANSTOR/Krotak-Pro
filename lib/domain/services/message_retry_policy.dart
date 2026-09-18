import '../entities/message.dart';

/// Retry policy aligned with help-center screenshots: max 3 attempts.
/// Transient failures stay retryable; exhausted attempts → failedMaxAttempts.
final class MessageRetryPolicy {
  const MessageRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 3),
    this.maxDelay = const Duration(minutes: 30),
    this.confirmPendingTimeout = const Duration(minutes: 15),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Screenshot rule: if stuck awaiting network confirm > 15 minutes, re-queue.
  final Duration confirmPendingTimeout;

  bool isRetryableCode(String code) => const {
        'commercial_flow_misconfigured',
        'delivery_phone_missing',
        'delivery_state_invalid',
        'sms_delivery_failed',
        'sms_delivery_state_persist_failed',
        'transfer_credit_failed',
        'transfer_sale_commit_failed',
        'transfer_sale_recovery_failed',
        'transfer_delivery_recovery_failed',
        'transfer_ledger_missing',
        'message_save_failed',
        'message_status_update_failed',
        RejectionRetryHints.voucherSendFailed,
      }.contains(code);

  bool canRetry(int attempts) => attempts < maxAttempts;

  Duration delayForAttempt(int attempt) {
    final n = attempt.clamp(1, maxAttempts);
    var seconds = baseDelay.inSeconds;
    for (var i = 1; i < n; i++) {
      seconds = (seconds * 2).clamp(baseDelay.inSeconds, maxDelay.inSeconds);
    }
    return Duration(seconds: seconds > maxDelay.inSeconds ? maxDelay.inSeconds : seconds);
  }

  /// Status after a failed attempt.
  MessageProcessingStatus statusAfterFailure(String code, {required int attemptsAfter}) {
    if (!isRetryableCode(code)) {
      return MessageProcessingStatus.rejected;
    }
    if (!canRetry(attemptsAfter)) {
      return MessageProcessingStatus.failedMaxAttempts;
    }
    return MessageProcessingStatus.failed;
  }

  /// Whether a sending/pending message should be re-queued by timeout.
  bool shouldRequeueAfterConfirmTimeout({
    required MessageProcessingStatus status,
    required DateTime lastAttemptAt,
    DateTime? now,
  }) {
    if (status != MessageProcessingStatus.sending &&
        status != MessageProcessingStatus.pending) {
      return false;
    }
    final clock = now ?? DateTime.now().toUtc();
    return clock.difference(lastAttemptAt) >= confirmPendingTimeout;
  }
}

/// Local string aliases so policy does not hard-depend on RejectionCodes catalog.
abstract final class RejectionRetryHints {
  static const voucherSendFailed = 'voucher_send_failed';
}
