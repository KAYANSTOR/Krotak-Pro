import 'package:flutter_test/flutter_test.dart';
import 'package:krotak_pro/domain/domain.dart';

void main() {
  test('exactly 13 documented rejection codes', () {
    expect(RejectionCodes.all, hasLength(13));
    expect(RejectionCodes.isKnown('voucherSendFailed'), isTrue);
    expect(RejectionCodes.isKnown('notARealCode'), isFalse);
    expect(RejectionCodes.isKnown(null), isFalse);
  });

  test('screenshot codes are all present', () {
    const fromShots = [
      'voucherSendFailed',
      'voucherUnavailable',
      'missingFields',
      'categoryMismatch',
      'blacklisted',
      'parseFailure',
      'noActiveTemplate',
      'unknownSender',
      'duplicateTransaction',
      'invalidFormat',
      'licenseBlocked',
      'creditLimitExceeded',
      'other',
    ];
    for (final code in fromShots) {
      expect(RejectionCodes.all, contains(code), reason: code);
    }
  });
}
