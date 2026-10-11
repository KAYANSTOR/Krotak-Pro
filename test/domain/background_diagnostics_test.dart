import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/domain/entities/background_diagnostics.dart';
import 'package:net_app/domain/services/local_system_health_service.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/platform/system_diagnostics_bridge.dart';

/// WP-9 — تشخيص الخلفية: الأرماز المنصّية تُترجم إلى نصوص عربية
/// ولا يتسرّب أي رمز أو نص لاتيني إلى الواجهة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kayan.net/diagnostics');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => handler(call));
  }

  test('كل رمز سبب إنهاء معروف له اسم عربي بلا لاتيني', () {
    const expected = <String, String>{
      'unknown': 'سبب غير معروف',
      'anr': 'التطبيق لا يستجيب',
      'low_memory': 'ذاكرة منخفضة',
      'excessive_resource_usage': 'استهلاك موارد زائد',
      'user_requested': 'إغلاق من المستخدم',
      'freezer': 'تجميد من النظام',
    };
    expected.forEach((code, label) {
      expect(ProcessExitReasonCode.fromCode(code).arabicLabel, label);
    });
    for (final value in ProcessExitReasonCode.values) {
      expect(RegExp('[A-Za-z]').hasMatch(value.arabicLabel), isFalse,
          reason: 'نص لاتيني في ${value.code}');
    }
  });

  test('كل حدث خدمة له اسم عربي والمجهول لا ينكشف', () {
    expect(
      BackgroundServiceEventCode.fromCode('timeout').arabicLabel,
      'انتهت مهلة النوع الأمامي',
    );
    expect(
      BackgroundServiceEventCode.fromCode('start_rejected').arabicLabel,
      'رفض النظام تشغيل الخدمة',
    );
    expect(
      BackgroundServiceEventCode.fromCode('not-a-code'),
      BackgroundServiceEventCode.unknown,
    );
    for (final value in BackgroundServiceEventCode.values) {
      expect(RegExp('[A-Za-z]').hasMatch(value.arabicLabel), isFalse);
    }
  });

  test('الوصف اللاتيني من النظام يُحذف ولا يظهر للمستخدم', () {
    final payload = BackgroundDiagnostics.fromPayload(
      exitReasons: <Object?>[
        <Object?, Object?>{
          'code': 'anr',
          'timestampMillis': 1_700_000_000_000,
          'description': 'Input dispatching timed out (raw stack)',
        },
        <Object?, Object?>{
          'code': 'low_memory',
          'timestampMillis': 1_700_000_100_000,
          'description': 'ذاكرة منخفضة جدًا',
        },
      ],
      serviceEvents: <Object?>[
        <Object?, Object?>{
          'event': 'timeout',
          'atMillis': 1_700_000_200_000,
          'detail': 'fgsType=8',
        },
      ],
      targetSdk: 36,
    );

    expect(payload.exitReasons, hasLength(2));
    expect(payload.exitReasons.first.code, ProcessExitReasonCode.anr);
    expect(payload.exitReasons.first.description, isEmpty);
    expect(payload.exitReasons.last.description, 'ذاكرة منخفضة جدًا');
    expect(payload.serviceEvents.single.detail, 'fgsType=8');
    expect(payload.targetSdk, 36);
    expect(payload.isEmpty, isFalse);
  });

  test('حمولة تالفة لا تُسقط الشاشة', () {
    final payload = BackgroundDiagnostics.fromPayload(
      exitReasons: <Object?>[null, 'x', <Object?, Object?>{'code': 'anr'}],
      serviceEvents: <Object?>[<Object?, Object?>{'event': 'started'}],
    );
    expect(payload.exitReasons, isEmpty);
    expect(payload.serviceEvents, isEmpty);
    expect(payload.isEmpty, isTrue);
  });

  test('الخدمة تقرأ التشخيص من القناة وتُعيد نجاحًا', () async {
    mockChannel((call) async {
      switch (call.method) {
        case 'exitReasons':
          return <Object?>[
            <Object?, Object?>{
              'code': 'anr',
              'timestampMillis': 1_700_000_000_000,
              'description': '',
            },
          ];
        case 'keepAliveEvents':
          return <Object?>[
            <Object?, Object?>{
              'event': 'started',
              'atMillis': 1_700_000_000_000,
              'detail': '',
            },
          ];
        case 'targetSdk':
          return 36;
        default:
          return null;
      }
    });
    final service = LocalSystemHealthService(
      bridge: SystemDiagnosticsBridge(),
      clock: FixedClock(DateTime(2026, 10, 10)),
    );
    final result = await service.backgroundDiagnostics();
    expect(result, isA<Success<BackgroundDiagnostics>>());
    final payload = (result as Success<BackgroundDiagnostics>).value;
    expect(payload.exitReasons.single.code, ProcessExitReasonCode.anr);
    expect(payload.serviceEvents.single.code, BackgroundServiceEventCode.started);
    expect(payload.targetSdk, 36);
  });

  test('غياب القناة (منصّة غير أندرويد) يُعيد تشخيصًا فارغًا بلا فشل', () async {
    final service = LocalSystemHealthService(
      bridge: SystemDiagnosticsBridge(),
      clock: FixedClock(DateTime(2026, 10, 10)),
    );
    final result = await service.backgroundDiagnostics();
    expect(result, isA<Success<BackgroundDiagnostics>>());
    expect((result as Success<BackgroundDiagnostics>).value.isEmpty, isTrue);
  });
}
