import '../entities/message.dart';

/// Retry budget and backoff for message delivery / recovery (Phase 1 / Phase 4).
///
/// Defaults match commercial targets: first retry within ~1s, exponential
/// growth capped, and a 15-minute confirm timeout for stuck sending/pending.
final class MessageRetryPolicy {
  const MessageRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 30),
    this.confirmPendingTimeout = const Duration(minutes: 15),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration confirmPendingTimeout;

  bool isExhausted(int attempts) => attempts >= maxAttempts;

  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    var seconds = baseDelay.inSeconds;
    for (var i = 1; i < attempt; i++) {
      seconds = (seconds * 2).clamp(baseDelay.inSeconds, maxDelay.inSeconds);
    }
    return Duration(seconds: seconds > maxDelay.inSeconds ? maxDelay.inSeconds : seconds);
  }

  bool shouldRequeueAfterConfirmTimeout({
    required MessageProcessingStatus status,
    required DateTime lastAttemptAt,
    required DateTime now,
  }) {
    if (status != MessageProcessingStatus.sending &&
        status != MessageProcessingStatus.pending) {
      return false;
    }
    return now.difference(lastAttemptAt) >= confirmPendingTimeout;
  }
}
