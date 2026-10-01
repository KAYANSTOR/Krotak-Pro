import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/platform/notification_bridge.dart';

void main() {
  testWidgets('notification bridge calls canonical native methods', (_) async {
    const channel = MethodChannel('com.kayan.net/notifications');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isAccessGranted') return true;
      return null;
    });

    final bridge = NotificationBridge(methods: channel);
    expect(await bridge.isAccessGranted(), isTrue);
    await bridge.openAccessSettings();
    expect(calls, ['isAccessGranted', 'openAccessSettings']);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
