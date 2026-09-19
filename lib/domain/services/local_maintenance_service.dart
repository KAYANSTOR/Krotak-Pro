import '../../core/clock.dart';
import '../../core/result.dart';
import '../../data/database/app_database.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Smart retention purge + SQLite deep clean (VACUUM / ANALYZE).
final class LocalMaintenanceService {
  const LocalMaintenanceService({
    required this.messages,
    required this.clock,
    this.database,
    this.rejectedRetention = const Duration(days: 30),
    this.processedRetention = const Duration(days: 3),
    this.failedMaxRetention = const Duration(days: 30),
  });

  final MessageRepository messages;
  final Clock clock;
  final AppDatabase? database;
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

  /// Rebuilds SQLite indexes / statistics (VACUUM + ANALYZE + PRAGMA optimize).
  Future<Result<DeepCleanReport>> runDeepClean() async {
    final db = database;
    if (db == null) {
      return const Failure(
        AppFailure(code: 'deep_clean_unavailable', message: 'Database not available'),
      );
    }
    final sw = Stopwatch()..start();
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.customStatement('VACUUM');
      await db.customStatement('ANALYZE');
      await db.customStatement('PRAGMA optimize');
      sw.stop();
      return Success(DeepCleanReport(durationMs: sw.elapsedMilliseconds));
    } catch (e) {
      return Failure(
        AppFailure(code: 'deep_clean_failed', message: e.toString()),
      );
    }
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
}

final class DeepCleanReport {
  const DeepCleanReport({required this.durationMs});
  final int durationMs;
}
