import 'package:flutter_test/flutter_test.dart';
import 'package:krotak_pro/domain/phone_normalizer.dart';

void main() {
  group('PhoneNormalizer.canonicalize', () {
    test('maps common Yemen forms to national number', () {
      expect(PhoneNormalizer.canonicalize('777123456'), '777123456');
      expect(PhoneNormalizer.canonicalize('0777123456'), '777123456');
      expect(PhoneNormalizer.canonicalize('+967777123456'), '777123456');
      expect(PhoneNormalizer.canonicalize('00967777123456'), '777123456');
      expect(PhoneNormalizer.canonicalize('967777123456'), '777123456');
    });

    test('rejects empty and non-phone', () {
      expect(PhoneNormalizer.canonicalize(''), isNull);
      expect(PhoneNormalizer.canonicalize('abc'), isNull);
      expect(PhoneNormalizer.canonicalize('123'), isNull);
    });
  });

  group('PhoneNormalizer.lookupKeys', () {
    test('includes variants for resolution', () {
      final keys = PhoneNormalizer.lookupKeys('+967777123456');
      expect(keys, contains('777123456'));
      expect(keys, contains('0777123456'));
      expect(keys, contains('+967777123456'));
    });
  });

  group('PhoneNormalizer.samePhone', () {
    test('equates formats', () {
      expect(PhoneNormalizer.samePhone('0777123456', '+967777123456'), isTrue);
      expect(PhoneNormalizer.samePhone('777123456', '777999999'), isFalse);
    });
  });
}
