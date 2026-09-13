import '../entities/message.dart';

/// Phase 4 retry policy. Only transient failures are retried automatically.
final class MessageRetryPolicy {
  const MessageRetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 30),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

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

  MessageProcessingStatus statusAfterFailure(String code) =>
      isRetryableCode(code) ? MessageProcessingStatus.failed : MessageProcessingStatus.rejected;
}
