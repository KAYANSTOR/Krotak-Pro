import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/message_pipeline_trace.dart';

/// معيار تجاري: من الاستلام حتى بدء الـdispatch أقل من 10 ثوانٍ
/// في مسار محلي مُقاس (بدون انتظار شبكة).
void main() {
  test('commercial SLA: receiveToDispatchMs under 10000 for hot path stages', () {
    final received = DateTime.utc(2026, 9, 21, 8, 0, 0);
    final trace = MessagePipelineTrace(messageId: 'msg-sla', receivedAt: received);
    // مسار ساخن واقعي: parse ~50ms، commit ~200ms، dispatch kick فوري
    trace.markParsed(received.add(const Duration(milliseconds: 50)));
    trace.markCommitted(received.add(const Duration(milliseconds: 250)));
    trace.markDispatchStarted(received.add(const Duration(milliseconds: 280)));
    trace.markSendResult(success: true, at: received.add(const Duration(milliseconds: 900)));

    expect(trace.receiveToDispatchMs, isNotNull);
    expect(trace.receiveToDispatchMs! < 10000, isTrue);
    expect(trace.receiveToSendResultMs! < 10000, isTrue);
    final json = trace.toJson();
    expect(json['receiveToDispatchMs'], lessThan(10000));
  });

  test('commercial SLA fails if artificial multi-minute delay introduced', () {
    final received = DateTime.utc(2026, 9, 21, 8, 0, 0);
    final trace = MessagePipelineTrace(messageId: 'msg-slow', receivedAt: received);
    trace.markDispatchStarted(received.add(const Duration(minutes: 2)));
    expect(trace.receiveToDispatchMs! >= 10000, isTrue);
  });
}
