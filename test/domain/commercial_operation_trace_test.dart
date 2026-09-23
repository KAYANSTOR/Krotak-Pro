import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/services/commercial_operation_trace_service.dart';

void main() {
  late AppDatabase database;
  late LocalAuditLogRepository audits;
  late CommercialOperationTraceService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    audits = LocalAuditLogRepository(database);
    service = CommercialOperationTraceService(audits);
  });

  tearDown(() async {
    await database.close();
  });

  test('lookup groups customer, card, message and operation from payload', () async {
    final now = DateTime.utc(2026, 9, 23, 12);
    await audits.append(AuditLog(
      id: 'a1',
      entityType: 'message',
      entityId: 'msg-9',
      action: 'sale_committed',
      occurredAt: now,
      payloadJson: '{"operationId":"op-77","cardId":"card-3","customerId":"cust-2"}',
    ));
    await audits.append(AuditLog(
      id: 'a2',
      entityType: 'card',
      entityId: 'card-3',
      action: 'reserved',
      occurredAt: now.add(const Duration(seconds: 1)),
      payloadJson: '{"operationId":"op-77"}',
    ));
    await audits.append(AuditLog(
      id: 'a3',
      entityType: 'message',
      entityId: 'msg-9',
      action: 'sms_delivered',
      occurredAt: now.add(const Duration(seconds: 2)),
      payloadJson: '{"operationId":"op-77"}',
    ));

    final result = await service.lookup('op-77');
    expect(result, isA<Success<CommercialOperationTrace>>());
    final trace = (result as Success<CommercialOperationTrace>).value;
    expect(trace.events.length, 3);
    expect(trace.operationIds, contains('op-77'));
    expect(trace.customerIds, contains('cust-2'));
    expect(trace.cardIds, contains('card-3'));
    expect(trace.messageIds, contains('msg-9'));
    expect(trace.actions, containsAll(['sale_committed', 'reserved', 'sms_delivered']));
  });

  test('empty query returns empty trace', () async {
    final result = await service.lookup('   ');
    final trace = (result as Success<CommercialOperationTrace>).value;
    expect(trace.events, isEmpty);
  });
}
