import 'entities/message.dart';

/// Allowed transitions for [MessageProcessingStatus].
///
/// Keeps operational semantics from the conversion plan in one place so
/// widgets and ad-hoc service checks do not invent new transitions.
final class MessageStatusMachine {
  const MessageStatusMachine();

  /// Returns true when moving from [from] to [to] is permitted.
  bool canTransition(MessageProcessingStatus from, MessageProcessingStatus to) {
    if (from == to) return true;
    return switch (from) {
      MessageProcessingStatus.received =>
        to == MessageProcessingStatus.parsed ||
            to == MessageProcessingStatus.rejected ||
            to == MessageProcessingStatus.failed,
      MessageProcessingStatus.parsed =>
        to == MessageProcessingStatus.pending ||
            to == MessageProcessingStatus.sending ||
            to == MessageProcessingStatus.processed ||
            to == MessageProcessingStatus.rejected ||
            to == MessageProcessingStatus.failed ||
            to == MessageProcessingStatus.failedMaxAttempts,
      MessageProcessingStatus.pending =>
        to == MessageProcessingStatus.sending ||
            to == MessageProcessingStatus.parsed ||
            to == MessageProcessingStatus.recovered ||
            to == MessageProcessingStatus.rejected ||
            to == MessageProcessingStatus.failed ||
            to == MessageProcessingStatus.failedMaxAttempts,
      MessageProcessingStatus.sending =>
        to == MessageProcessingStatus.processed ||
            to == MessageProcessingStatus.pending ||
            to == MessageProcessingStatus.failed ||
            to == MessageProcessingStatus.failedMaxAttempts,
      MessageProcessingStatus.processed => false,
      MessageProcessingStatus.rejected =>
        to == MessageProcessingStatus.recovered,
      MessageProcessingStatus.failed =>
        to == MessageProcessingStatus.recovered ||
            to == MessageProcessingStatus.failedMaxAttempts ||
            to == MessageProcessingStatus.pending,
      MessageProcessingStatus.failedMaxAttempts =>
        to == MessageProcessingStatus.recovered,
      MessageProcessingStatus.recovered =>
        to == MessageProcessingStatus.parsed ||
            to == MessageProcessingStatus.pending ||
            to == MessageProcessingStatus.sending,
    };
  }

  /// Terminal statuses that must not be auto-retried without explicit recovery.
  bool isTerminal(MessageProcessingStatus status) =>
      status == MessageProcessingStatus.processed ||
      status == MessageProcessingStatus.rejected ||
      status == MessageProcessingStatus.failedMaxAttempts;

  /// Statuses that may appear in the pending-attention queue.
  bool isAttention(MessageProcessingStatus status) =>
      status == MessageProcessingStatus.pending ||
      status == MessageProcessingStatus.failed ||
      status == MessageProcessingStatus.failedMaxAttempts ||
      status == MessageProcessingStatus.sending;
}
