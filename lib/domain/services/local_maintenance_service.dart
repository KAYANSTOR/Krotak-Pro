import '../../core/clock.dart';
import '../../core/result.dart';
import '../../data/database/app_database.dart' hide IncomingMessage;
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

  static const int defaultWarningThresholdBytes = 80 * 1024 * 1024;

  /// Reads live SQLite page stats. Does not touch ledger or inventory rows.
  Future<Result<SqliteStorageSnapshot>> measureStorage({
    int warningThresholdBytes = defaultWarningThresholdBytes,
  }) async {
    final db = database;
    if (db == null) {
      return const Failure(
        AppFailure(
          code: 'storage_measure_unavailable',
          message: 'Database not available',
        ),
      );
    }
    try {
      final pageCount = await _pragmaInt(db, 'page_count');
      final pageSize = await _pragmaInt(db, 'page_size');
      final freelist = await _pragmaInt(db, 'freelist_count');
      final usedBytes = pageCount * pageSize;
      final reclaimableBytes = freelist * pageSize;
      return Success(
        SqliteStorageSnapshot(
          pageCount: pageCount,
          pageSize: pageSize,
          usedBytes: usedBytes,
          reclaimableBytes: reclaimableBytes,
          warning: usedBytes >= warningThresholdBytes,
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure(code: 'storage_measure_failed', message: e.toString()),
      );
    }
  }

  Future<int> _pragmaInt(AppDatabase db, String name) async {
    final rows = await db.customSelect('PRAGMA $name').get();
    if (rows.isEmpty) return 0;
    final raw = rows.first.data.values.first;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
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

final class SqliteStorageSnapshot {
  const SqliteStorageSnapshot({
    required this.pageCount,
    required this.pageSize,
    required this.usedBytes,
    required this.reclaimableBytes,
    required this.warning,
  });

  final int pageCount;
  final int pageSize;
  final int usedBytes;
  final int reclaimableBytes;
  final bool warning;
}

String formatStorageBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}
