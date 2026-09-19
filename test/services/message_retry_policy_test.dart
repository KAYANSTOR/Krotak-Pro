import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/message_retry_policy.dart';

void main() {
  const policy = MessageRetryPolicy();

  test('retries only transient failures', () {
    expect(policy.isRetryableCode('sms_delivery_failed'), isTrue);
    expect(policy.isRetryableCode('out_of_stock'), isFalse);
    expect(policy.isRetryableCode('voucherSendFailed'), isTrue);
    expect(policy.isRetryableCode('voucher_send_failed'), isTrue);
  });

  test('uses bounded exponential backoff with maxAttempts=3', () {
    expect(policy.maxAttempts, 3);
    expect(policy.delayForAttempt(1), const Duration(seconds: 2));
    expect(policy.delayForAttempt(2), const Duration(seconds: 4));
    expect(policy.delayForAttempt(3), const Duration(seconds: 8));
    // Clamped to maxAttempts=3 → same as attempt 3.
    expect(policy.delayForAttempt(99), const Duration(seconds: 8));
  });

  test('statusAfterFailure maps exhausted to failedMaxAttempts', () {
    expect(
      policy.statusAfterFailure('out_of_stock', attemptsAfter: 1),
      MessageProcessingStatus.rejected,
    );
    expect(
      policy.statusAfterFailure('sms_delivery_failed', attemptsAfter: 1),
      MessageProcessingStatus.failed,
    );
    expect(
      policy.statusAfterFailure('sms_delivery_failed', attemptsAfter: 3),
      MessageProcessingStatus.failedMaxAttempts,
    );
  });

  test('confirm-pending timeout is 15 minutes', () {
    expect(policy.confirmPendingTimeout, const Duration(minutes: 15));
    final last = DateTime.utc(2026, 9, 17, 12, 0);
    expect(
      policy.shouldRequeueAfterConfirmTimeout(
        status: MessageProcessingStatus.sending,
        lastAttemptAt: last,
        now: last.add(const Duration(minutes: 14)),
      ),
      isFalse,
    );
    expect(
      policy.shouldRequeueAfterConfirmTimeout(
        status: MessageProcessingStatus.sending,
        lastAttemptAt: last,
        now: last.add(const Duration(minutes: 15)),
      ),
      isTrue,
    );
  });
}
