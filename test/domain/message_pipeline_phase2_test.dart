import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/message_pipeline_trace.dart';

void main() {
  group('MessagePipelineTrace', () {
    test('computes receiveToDispatchMs and receiveToSendResultMs', () {
      final received = DateTime.utc(2026, 9, 21, 10, 0, 0);
      final trace = MessagePipelineTrace(
        messageId: 'm1',
        receivedAt: received,
      );
      trace.markParsed(received.add(const Duration(milliseconds: 120)));
      trace.markCommitted(received.add(const Duration(milliseconds: 800)));
      trace.markDispatchStarted(received.add(const Duration(milliseconds: 950)));
      trace.markSendResult(
        success: true,
        at: received.add(const Duration(milliseconds: 1100)),
      );

      expect(trace.receiveToDispatchMs, 950);
      expect(trace.receiveToSendResultMs, 1100);
      expect(trace.sendOutcome, 'success');

      final json = trace.toJson();
      expect(json['receiveToDispatchMs'], 950);
      expect(json['sendOutcome'], 'success');
      expect(json['messageId'], isNull); // not in toJson by design
      expect(json['receivedAt'], received.toIso8601String());
    });

    test('null durations when stages not reached', () {
      final trace = MessagePipelineTrace(
        messageId: 'm2',
        receivedAt: DateTime.utc(2026, 9, 21),
      );
      expect(trace.receiveToDispatchMs, isNull);
      expect(trace.receiveToSendResultMs, isNull);
    });

    test('commercial target under 10s is expressible in metrics', () {
      final received = DateTime.utc(2026, 9, 21, 12, 0, 0);
      final trace = MessagePipelineTrace(messageId: 'm3', receivedAt: received);
      trace.markDispatchStarted(received.add(const Duration(seconds: 3)));
      expect(trace.receiveToDispatchMs! < 10000, isTrue);
    });
  });
}
