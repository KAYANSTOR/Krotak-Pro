import '../../core/clock.dart';
import '../../core/result.dart';
import '../../data/database/app_database.dart' hide IncomingMessage;
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Published retention windows. Financial ledger, cards, and customers are never auto-purged.
final class RetentionPolicy {
  const RetentionPolicy();

  static const int rejectedDays = 30;
  static const int processedDays = 3;
  static const int failedMaxDays = 30;

  static const String summaryAr =
      'تُحذف رسائل المعالجة بعد 3 أيام، والمرفوضة وبعد أقصى المحاولات بعد 30 يوماً. '
      'دفتر الحسابات والكروت والعملاء وسجل التدقيق لا تُحذف تلقائياً.';
}

/// Smart retention purge + SQLite deep clean (VACUUM / ANALYZE).
final class LocalMaintenanceService {
  const LocalMaintenanceService({
    required this.messages,
    required this.clock,
    this.database,
    this.rejectedRetention = const Duration(days: RetentionPolicy.rejectedDays),
    this.processedRetention = const Duration(days: RetentionPolicy.processedDays),
    this.failedMaxRetention = const Duration(days: RetentionPolicy.failedMaxDays),
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


  /// Logical SQLite size from page_count * page_size, plus reclaimable freelist.
  Future<Result<DatabaseSizeReport>> inspectDatabase() async {
    final db = database;
    if (db == null) {
      return const Failure(
        AppFailure(code: 'size_unavailable', message: 'Database not available'),
      );
    }
    try {
      final pageSize = await _pragmaInt(db, 'page_size');
      final pageCount = await _pragmaInt(db, 'page_count');
      final freelist = await _pragmaInt(db, 'freelist_count');
      final messages = await _count(db, 'incoming_messages');
      return Success(
        DatabaseSizeReport(
          pageSize: pageSize,
          pageCount: pageCount,
          freelistCount: freelist,
          incomingMessageCount: messages,
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure(code: 'size_failed', message: e.toString()),
      );
    }
  }

  Future<int> _pragmaInt(AppDatabase db, String name) async {
    final rows = await db.customSelect('PRAGMA $name').get();
    if (rows.isEmpty) return 0;
    final row = rows.first.data;
    final value = row.values.isEmpty ? 0 : row.values.first;
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  Future<int> _count(AppDatabase db, String table) async {
    final rows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
    if (rows.isEmpty) return 0;
    final value = rows.first.data['c'];
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
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

final class DatabaseSizeReport {
  const DatabaseSizeReport({
    required this.pageSize,
    required this.pageCount,
    required this.freelistCount,
    required this.incomingMessageCount,
  });

  final int pageSize;
  final int pageCount;
  final int freelistCount;
  final int incomingMessageCount;

  int get logicalBytes => pageSize * pageCount;
  int get reclaimableBytes => pageSize * freelistCount;

  String get logicalLabel => formatBytes(logicalBytes);
  String get reclaimableLabel => formatBytes(reclaimableBytes);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} ك.ب';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(2)} م.ب';
  return '${(mb / 1024).toStringAsFixed(2)} ج.ب';
}
