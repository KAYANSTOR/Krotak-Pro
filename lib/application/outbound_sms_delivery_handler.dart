import 'dart:async';

import '../core/clock.dart';
import '../core/id_generator.dart';
import '../domain/entities/audit.dart';
import '../domain/repositories/repositories.dart';
import '../platform/sms_bridge.dart';

/// Persists carrier delivery reports without touching the ledger.
///
/// Sent-status is already awaited on the method channel. Delivery arrives
/// later via [SmsBridge.outboundEvents] and is audit-only so a failed
/// delivery never reverses a committed sale.
final class OutboundSmsDeliveryHandler {
  OutboundSmsDeliveryHandler({
    required this.bridge,
    required this.auditLogs,
    required this.clock,
    required this.ids,
  });

  final SmsBridge bridge;
  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;

  StreamSubscription<SmsDeliveryEvent>? _sub;
  final List<SmsDeliveryEvent> received = <SmsDeliveryEvent>[];

  void start() {
    _sub ??= bridge.outboundEvents.listen(_onEvent, onError: (_) {});
  }

  Future<void> record(SmsDeliveryEvent event) async {
    await _onEvent(event);
  }

  Future<void> _onEvent(SmsDeliveryEvent event) async {
    received.add(event);
    await auditLogs.append(
      AuditLog(
        id: ids.next('sms-delivery'),
        entityType: 'outbound_sms',
        entityId: '${event.requestId}',
        action: event.delivered ? 'sms_delivered' : 'sms_delivery_failed',
        occurredAt: clock.now(),
        payloadJson:
            '{"to":"${event.to}","delivered":"${event.delivered}","resultCode":"${event.resultCode}"}',
      ),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
