import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/cloud_account_service.dart';

defaultPhoneTests() {
  test('normalizes local Yemeni phone numbers to the international form', () {
    expect(
      CloudAccountService.normalizePhone('773303455'),
      '967773303455',
    );
    expect(
      CloudAccountService.normalizePhone('0773303455'),
      '967773303455',
    );
    expect(
      CloudAccountService.normalizePhone('+967 773 303 455'),
      '967773303455',
    );
  });

  test('accepts Arabic-Indic phone digits', () {
    expect(
      CloudAccountService.normalizePhone('٧٧٣٣٠٣٤٥٥'),
      '967773303455',
    );
    expect(
      CloudAccountService.isValidPhone('٧٧٣٣٠٣٤٥٥'),
      isTrue,
    );
  });
}

void main() {
  group('CloudAccountService phone handling', defaultPhoneTests);
}
