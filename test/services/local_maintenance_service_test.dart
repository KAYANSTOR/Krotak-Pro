import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:drift/native.dart';
import 'package:net_app/data/database/app_database.dart' show AppDatabase;
import 'package:net_app/domain/services/local_maintenance_service.dart';

import '../helpers/in_memory_repositories.dart';

final class _Clock implements Clock {
  _Clock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  extraSizeTests();

  test('purges rejected older than 30 days and keeps recent', () async {
    final messages = InMemoryMessageRepository();
    final now = DateTime.utc(2026, 9, 17);
    await messages.save(
      IncomingMessage(
        id: 'old-r',
        sender: 'JAIB',
        body: 'x',
        receivedAt: now.subtract(const Duration(days: 40)),
        status: MessageProcessingStatus.rejected,
      ),
    );
    await messages.save(
      IncomingMessage(
        id: 'new-r',
        sender: 'JAIB',
        body: 'y',
        receivedAt: now.subtract(const Duration(days: 2)),
        status: MessageProcessingStatus.rejected,
      ),
    );
    await messages.save(
      IncomingMessage(
        id: 'old-p',
        sender: 'JAIB',
        body: 'z',
        receivedAt: now.subtract(const Duration(days: 10)),
        status: MessageProcessingStatus.processed,
      ),
    );

    final svc = LocalMaintenanceService(
      messages: messages,
      clock: _Clock(now),
    );
    final report = await svc.purgeExpiredMessages();
    expect(report, isA<Success<MaintenanceReport>>());
    final r = (report as Success<MaintenanceReport>).value;
    expect(r.deletedRejected, 1);
    expect(r.deletedProcessed, 1);

    final left = await messages.listByStatus(MessageProcessingStatus.rejected);
    expect((left as Success).value.single.id, 'new-r');
  });
}

void extraSizeTests() {
  test('formats sqlite size labels', () {
    expect(formatBytes(512), '512 بايت');
    expect(formatBytes(2048), '2.0 ك.ب');
    final report = DatabaseSizeReport(
      pageSize: 4096,
      pageCount: 10,
      freelistCount: 2,
      incomingMessageCount: 4,
    );
    expect(report.logicalBytes, 40960);
    expect(report.reclaimableBytes, 8192);
  });

  test('inspectDatabase reads page size without deleting rows', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final svc = LocalMaintenanceService(
      messages: InMemoryMessageRepository(),
      clock: _Clock(DateTime.utc(2026, 10, 1)),
      database: database,
    );
    final result = await svc.inspectDatabase();
    expect(result, isA<Success<DatabaseSizeReport>>());
    final report = (result as Success<DatabaseSizeReport>).value;
    expect(report.pageSize, greaterThan(0));
    expect(report.pageCount, greaterThan(0));
    expect(report.logicalBytes, report.pageSize * report.pageCount);
  });

  test('التنظيف العميق ينفّذ REINDEX فعلاً ويقيس الحجم قبل/بعد [WP-3]', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final svc = LocalMaintenanceService(
      messages: InMemoryMessageRepository(),
      clock: _Clock(DateTime.utc(2026, 10, 1)),
      database: database,
    );

    // مصدر واحد لجمل التنظيف: REINDEX جزء فعلي لا وصف تسويقي.
    expect(LocalMaintenanceService.deepCleanStatements, contains('REINDEX'));
    expect(LocalMaintenanceService.deepCleanStatements, contains('VACUUM'));
    expect(LocalMaintenanceService.deepCleanStatements, contains('ANALYZE'));
    expect(LocalMaintenanceService.deepCleanStatements.first, contains('wal_checkpoint'));
    expect(LocalMaintenanceService.deepCleanStatements.last, contains('optimize'));

    final result = await svc.runDeepClean();
    expect(result, isA<Success<DeepCleanReport>>());
    final report = (result as Success<DeepCleanReport>).value;
    expect(report.hasSizeComparison, isTrue);
    expect(report.sizeBeforeBytes, greaterThan(0));
    expect(report.sizeAfterBytes, greaterThan(0));
    expect(report.reclaimedBytes, isNotNull);
  });

  test('فشل التنظيف العميق برسالة عربية بلا نص إنجليزي [WP-3]', () async {
    final svc = LocalMaintenanceService(
      messages: InMemoryMessageRepository(),
      clock: _Clock(DateTime.utc(2026, 10, 1)),
    );
    final deep = await svc.runDeepClean();
    final size = await svc.inspectDatabase();
    for (final result in <Result<Object>>[deep, size]) {
      expect(result, isA<Failure<Object>>());
      final message = (result as Failure<Object>).error.message;
      expect(RegExp('[A-Za-z]').hasMatch(message), isFalse, reason: message);
    }
  });
}
