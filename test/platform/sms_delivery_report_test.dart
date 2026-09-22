import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/platform/sms_bridge.dart';
import 'package:net_app/application/outbound_sms_delivery_handler.dart';

void main() {
  test('SmsSendReceipt accepts map from native sent PendingIntent', () {
    final receipt = SmsSendReceipt.fromPlatform(
      {'sent': true, 'requestId': 42, 'to': '777000111'},
      fallbackTo: 'fallback',
    );
    expect(receipt.sent, isTrue);
    expect(receipt.requestId, 42);
    expect(receipt.to, '777000111');
  });

  test('SmsSendReceipt accepts legacy boolean success', () {
    final receipt = SmsSendReceipt.fromPlatform(true, fallbackTo: '770');
    expect(receipt.sent, isTrue);
    expect(receipt.to, '770');
    expect(receipt.requestId, isNull);
  });

  test('SmsDeliveryEvent maps carrier result', () {
    final delivered = SmsDeliveryEvent.fromPlatform({
      'type': 'sms_delivery',
      'requestId': 9,
      'to': '771234567',
      'delivered': true,
      'resultCode': -1,
    });
    expect(delivered.delivered, isTrue);
    expect(delivered.requestId, 9);

    final failed = SmsDeliveryEvent.fromPlatform({
      'requestId': 9,
      'to': '771234567',
      'delivered': false,
      'resultCode': 2,
    });
    expect(failed.delivered, isFalse);
    expect(failed.resultCode, 2);
  });

  test('delivery handler writes audit and never implies ledger reversal', () async {
    final repo = _MemAudit();
    final handler = OutboundSmsDeliveryHandler(
      bridge: SmsBridge(),
      auditLogs: repo,
      clock: FixedClock(DateTime.utc(2026, 9, 22, 8)),
      ids: SequentialIdGenerator(),
    );
    await handler.record(
      const SmsDeliveryEvent(
        requestId: 17,
        to: '777111222',
        delivered: false,
        resultCode: 2,
      ),
    );
    expect(repo.items, hasLength(1));
    expect(repo.items.single.action, 'sms_delivery_failed');
    expect(repo.items.single.entityType, 'outbound_sms');
    expect(repo.items.single.payloadJson, contains('777111222'));
  });
}

final class _MemAudit implements AuditLogRepository {
  final List<AuditLog> items = <AuditLog>[];

  @override
  Future<Result<void>> append(AuditLog log) async {
    items.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async {
    return Success(items.where((e) => e.entityType == entityType && e.entityId == entityId).toList());
  }
}
