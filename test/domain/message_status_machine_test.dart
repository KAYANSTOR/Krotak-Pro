import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/domain.dart';

void main() {
  const machine = MessageStatusMachine();

  test('received may move to parsed/rejected/failed only', () {
    expect(machine.canTransition(MessageProcessingStatus.received, MessageProcessingStatus.parsed), isTrue);
    expect(machine.canTransition(MessageProcessingStatus.received, MessageProcessingStatus.processed), isFalse);
    expect(machine.canTransition(MessageProcessingStatus.received, MessageProcessingStatus.sending), isFalse);
  });

  test('processed is terminal', () {
    expect(machine.isTerminal(MessageProcessingStatus.processed), isTrue);
    expect(machine.canTransition(MessageProcessingStatus.processed, MessageProcessingStatus.pending), isFalse);
  });

  test('recovered may re-enter pipeline', () {
    expect(machine.canTransition(MessageProcessingStatus.failedMaxAttempts, MessageProcessingStatus.recovered), isTrue);
    expect(machine.canTransition(MessageProcessingStatus.recovered, MessageProcessingStatus.parsed), isTrue);
  });

  test('attention statuses include pending and failed variants', () {
    expect(machine.isAttention(MessageProcessingStatus.pending), isTrue);
    expect(machine.isAttention(MessageProcessingStatus.failedMaxAttempts), isTrue);
    expect(machine.isAttention(MessageProcessingStatus.processed), isFalse);
  });
}
