import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/delivery_keep_alive_controller.dart';
import 'package:net_app/platform/delivery_keep_alive_bridge.dart';

/// عقد خدمة الحفاظ على تسليم الكروت في الخلفية.
///
/// ما يُثبته هذا الاختبار: متى يُطلب التشغيل، ومتى يُوقف، وأن الانتقال إلى
/// الخلفية **لا** يُوقف التسليم. ما يبقى جهازياً (خارج نطاق هذه الاختبارات):
/// أن النظام يقبل الخدمة فعلًا وأن العملية لا تُقتل أثناء نوم الجهاز.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.net/keepalive');
  late List<String> calls;
  late bool nativeActive;
  late bool nativeGranted;
  late bool rejectStart;

  late DeliveryKeepAliveBridge bridge;
  late DeliveryKeepAliveController controller;

  setUp(() {
    calls = <String>[];
    nativeActive = false;
    nativeGranted = true;
    rejectStart = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'start':
          if (rejectStart) {
            // نفس ما تفعله الطبقة الأصلية عند رفض النظام: استثناء يُبتلع.
            throw PlatformException(code: 'start_rejected');
          }
          nativeActive = true;
          return true;
        case 'stop':
          nativeActive = false;
          return false;
        case 'status':
          return <String, dynamic>{
            'active': nativeActive,
            'smsPermissionsGranted': nativeGranted,
          };
      }
      return null;
    });

    bridge = DeliveryKeepAliveBridge(channel: channel);
    controller = DeliveryKeepAliveController(bridge: bridge);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('starts the background service when sms permissions are granted', () async {
    final status = await controller.sync(smsPermissionsGranted: true);

    expect(calls, contains('start'));
    expect(status.active, isTrue);
    expect(controller.backgroundDeliveryActive, isTrue);
  });

  test('stops the background service once sms permissions are revoked', () async {
    await controller.sync(smsPermissionsGranted: true);
    calls.clear();

    final status = await controller.sync(smsPermissionsGranted: false);

    expect(calls, contains('stop'));
    expect(calls, isNot(contains('start')));
    expect(status.active, isFalse);
    expect(controller.backgroundDeliveryActive, isFalse);
  });

  test('going to the background never stops the service', () async {
    await controller.sync(smsPermissionsGranted: true);
    final afterStart = List<String>.from(calls);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ]) {
      await controller.handleLifecycle(state, smsPermissionsGranted: true);
    }

    // لا نداء جديد إطلاقًا: لا إيقاف ولا إعادة طلب من الخلفية (النظام يرفضه).
    expect(calls, afterStart);
    expect(controller.backgroundDeliveryActive, isTrue);
  });

  test('returning to the foreground re-asserts the service request', () async {
    await controller.sync(smsPermissionsGranted: true);
    calls.clear();

    await controller.handleLifecycle(
      AppLifecycleState.resumed,
      smsPermissionsGranted: true,
    );

    expect(calls, contains('start'));
    expect(calls, isNot(contains('stop')));
    expect(controller.syncCount, 2);
  });

  test('a rejected start request never throws and reports inactive', () async {
    rejectStart = true;

    final status = await controller.sync(smsPermissionsGranted: true);

    expect(status.active, isFalse);
    expect(controller.backgroundDeliveryActive, isFalse);
  });

  test('only the resumed lifecycle state re-asserts the request', () {
    expect(
      DeliveryKeepAliveController.shouldReassertOnLifecycle(
        AppLifecycleState.resumed,
      ),
      isTrue,
    );
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ]) {
      expect(
        DeliveryKeepAliveController.shouldReassertOnLifecycle(state),
        isFalse,
        reason: '$state must not re-assert or stop background delivery',
      );
    }
  });

  test('status decoding survives odd or missing platform payloads', () async {
    expect(DeliveryKeepAliveStatus.fromPlatform(null).active, isFalse);
    expect(DeliveryKeepAliveStatus.fromPlatform('unexpected').active, isFalse);
    expect(
      DeliveryKeepAliveStatus.fromPlatform(<String, dynamic>{}).active,
      isFalse,
    );
    // قيم منطقية قادمة من المنصّة كنصوص (بعض الجسور تُرسلها هكذا).
    final stringy = DeliveryKeepAliveStatus.fromPlatform(<String, dynamic>{
      'active': 'true',
      'smsPermissionsGranted': 'true',
    });
    expect(stringy.active, isTrue);
    expect(stringy.smsPermissionsGranted, isTrue);

    // وحمولة حقيقية عبر الجسر.
    nativeActive = true;
    final viaBridge = await bridge.status();
    expect(viaBridge.active, isTrue);
    expect(viaBridge.smsPermissionsGranted, isTrue);
  });

  test('a missing platform implementation degrades to inactive', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await bridge.start(), isFalse);
    expect((await bridge.status()).active, isFalse);
  });
}
