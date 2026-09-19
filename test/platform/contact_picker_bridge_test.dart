import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/platform/contact_picker_bridge.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kayan.net/diagnostics');

  bool granted = false;
  String? pickResult;

  setUp(() {
    granted = false;
    pickResult = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        switch (call.method) {
          case 'hasContactsPermission':
            return granted;
          case 'requestContacts':
            granted = true;
            return true;
          case 'pickContact':
            return pickResult;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('pickPhone requests permission then returns canonical number', () async {
    pickResult = '+967 773 303 455';
    final bridge = ContactPickerBridge();

    final phone = await bridge.pickPhone();

    expect(granted, isTrue, reason: 'طلب الصلاحية تلقائيًا عند الحاجة');
    expect(phone, '773303455', reason: 'تطبيع إلى الشكل المحلي 7XXXXXXXX');
  });

  test('pickPhone returns null when permission denied', () async {
    final bridge = ContactPickerBridge();
    final phone = await bridge.pickPhone();
    expect(phone, isNull);
  });

  test('pickPhone returns null for an empty/canceled picker result', () async {
    granted = true;
    final bridge = ContactPickerBridge();

    pickResult = null;
    expect(await bridge.pickPhone(), isNull);

    pickResult = '   ';
    expect(await bridge.pickPhone(), isNull);
  });

  test('pickPhone falls back to trimmed raw when normalization fails', () async {
    granted = true;
    pickResult = '01-800-NET';
    final bridge = ContactPickerBridge();

    final phone = await bridge.pickPhone();
    expect(phone, '01-800-NET');
  });

  test('permission probes swallow platform errors', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw PlatformException(code: 'boom');
      },
    );
    final bridge = ContactPickerBridge();

    expect(await bridge.hasContactsPermission(), isFalse);
    expect(await bridge.requestContactsPermission(), isFalse);
    expect(await bridge.pickPhone(), isNull);
  });
}
