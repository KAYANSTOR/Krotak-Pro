import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/message_retry_policy.dart';

void main() {
  const policy = MessageRetryPolicy();

  test('retries only transient failures', () {
    expect(policy.isRetryableCode('sms_delivery_failed'), isTrue);
    expect(policy.isRetryableCode('out_of_stock'), isFalse);
  });

  test('uses bounded exponential backoff', () {
    expect(policy.delayForAttempt(1), const Duration(seconds: 30));
    expect(policy.delayForAttempt(2), const Duration(seconds: 60));
    expect(policy.delayForAttempt(3), const Duration(seconds: 120));
    expect(policy.delayForAttempt(5), const Duration(minutes: 8));
    // Attempts are clamped to maxAttempts=5 before calculating the delay.
    expect(policy.delayForAttempt(99), const Duration(minutes: 8));
  });

  test('terminal status remains rejected', () {
    expect(policy.statusAfterFailure('out_of_stock'), MessageProcessingStatus.rejected);
    expect(policy.statusAfterFailure('sms_delivery_failed'), MessageProcessingStatus.failed);
  });
}
