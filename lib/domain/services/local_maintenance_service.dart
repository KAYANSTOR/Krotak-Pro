import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Phase 6 smart cleanup — retention policy from help-center screenshots.
///
/// | Kind | Keep |
/// |------|------|
/// | Rejected messages | 30 days |
/// | Processed (completed) messages | 3 days |
/// | Failed exhausted (failedMaxAttempts) | 30 days (same as rejected archive) |
///
/// **Never** deletes sales, transactions, cards, or customers.
final class LocalMaintenanceService {
  const LocalMaintenanceService({
    required this.messages,
    required this.clock,
    this.rejectedRetention = const Duration(days: 30),
    this.processedRetention = const Duration(days: 3),
    this.failedMaxRetention = const Duration(days: 30),
  });

  final MessageRepository messages;
  final Clock clock;
  final Duration rejectedRetention;
  final Duration processedRetention;
  final Duration failedMaxRetention;

  Future<Result<MaintenanceReport>> purgeExpiredMessages() async {
    final now = clock.now().toUtc();
    var deletedRejected = 0;
    var deletedProcessed = 0;
    var deletedFailedMax = 0;
    final errors = <String>[];

    final rejected = await messages.listByStatus(MessageProcessingStatus.rejected);
    if (rejected is Failure<List<IncomingMessage>>) {
      return Failure(rejected.error);
    }
    for (final m in (rejected as Success<List<IncomingMessage>>).value) {
      if (now.difference(m.receivedAt.toUtc()) < rejectedRetention) continue;
      final del = await messages.delete(m.id);
      if (del is Failure<void>) {
        errors.add('${m.id}:${del.error.code}');
      } else {
        deletedRejected++;
      }
    }

    final processed =
        await messages.listByStatus(MessageProcessingStatus.processed);
    if (processed is Failure<List<IncomingMessage>>) {
      return Failure(processed.error);
    }
    for (final m in (processed as Success<List<IncomingMessage>>).value) {
      if (now.difference(m.receivedAt.toUtc()) < processedRetention) continue;
      final del = await messages.delete(m.id);
      if (del is Failure<void>) {
        errors.add('${m.id}:${del.error.code}');
      } else {
        deletedProcessed++;
      }
    }

    final failedMax =
        await messages.listByStatus(MessageProcessingStatus.failedMaxAttempts);
    if (failedMax is Failure<List<IncomingMessage>>) {
      return Failure(failedMax.error);
    }
    for (final m in (failedMax as Success<List<IncomingMessage>>).value) {
      if (now.difference(m.receivedAt.toUtc()) < failedMaxRetention) continue;
      final del = await messages.delete(m.id);
      if (del is Failure<void>) {
        errors.add('${m.id}:${del.error.code}');
      } else {
        deletedFailedMax++;
      }
    }

    return Success(
      MaintenanceReport(
        deletedRejected: deletedRejected,
        deletedProcessed: deletedProcessed,
        deletedFailedMax: deletedFailedMax,
        errors: errors,
      ),
    );
  }
}

final class MaintenanceReport {
  const MaintenanceReport({
    required this.deletedRejected,
    required this.deletedProcessed,
    required this.deletedFailedMax,
    required this.errors,
  });

  final int deletedRejected;
  final int deletedProcessed;
  final int deletedFailedMax;
  final List<String> errors;

  int get totalDeleted =>
      deletedRejected + deletedProcessed + deletedFailedMax;
}
