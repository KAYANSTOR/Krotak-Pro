import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/platform/visible_storage_bridge.dart';

/// WP-S1 — اختبار قناة `com.kayan.net/storage` بمحاكاة كاملة:
/// النجاح يُرجع المسار الفعلي، والفشل يُترجم إلى رسالة عربية مفهومة،
/// وغياب المنصة (MissingPluginException) لا يُسقط التطبيق.
void main() {
  const channel = MethodChannel('com.kayan.net/storage');
  final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('saveToDownloads يُرسل الملف ويُرجع المسار الفعلي من المنصة', () async {
    final calls = <MethodCall>[];
    mock((call) async {
      calls.add(call);
      return {'path': 'content://downloads/42', 'uri': 'content://downloads/42'};
    });

    final result = await VisibleStorageBridge().saveToDownloads(
      bytes: bytes,
      fileName: 'backup.krt',
      mimeType: 'application/octet-stream',
      subfolder: 'Backups',
    );

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'content://downloads/42');
    expect(calls.single.method, 'saveToDownloads');
    final args = calls.single.arguments as Map;
    expect(args['fileName'], 'backup.krt');
    expect(args['subfolder'], 'Backups');
    expect(args['mimeType'], 'application/octet-stream');
    expect((args['bytes'] as Uint8List).length, 64);
  });

  test('saveImageToPictures يُرسل الصورة ويُرجع URI الصورة', () async {
    final calls = <MethodCall>[];
    mock((call) async {
      calls.add(call);
      return {'path': 'content://images/7', 'uri': 'content://images/7'};
    });

    final result = await VisibleStorageBridge().saveImageToPictures(
      bytes: bytes,
      fileName: 'إشعار-REF1.png',
    );

    expect((result as Success<String>).value, 'content://images/7');
    expect(calls.single.method, 'saveImageToPictures');
    expect((calls.single.arguments as Map)['fileName'], 'إشعار-REF1.png');
  });

  test('رد فارغ أو بلا مسار = فشل عربي مفهوم لا نجاح كاذب', () async {
    mock((call) async => <String, Object?>{});
    final empty = await VisibleStorageBridge().saveToDownloads(
      bytes: bytes,
      fileName: 'x.csv',
      mimeType: 'text/csv',
    );
    expect(empty, isA<Failure<String>>());
    expect((empty as Failure<String>).error.message, contains('تعذر حفظ الملف'));

    mock((call) async => null);
    final nulled = await VisibleStorageBridge().saveImageToPictures(
      bytes: bytes,
      fileName: 'x.png',
    );
    expect(nulled, isA<Failure<String>>());
    expect((nulled as Failure<String>).error.code, 'storage_failed');
  });

  test('رفض الصلاحية يُترجم إلى رسالة عربية', () async {
    mock((call) async => throw PlatformException(code: 'storage_permission_denied'));
    final result = await VisibleStorageBridge().saveToDownloads(
      bytes: bytes,
      fileName: 'backup.krt',
      mimeType: 'application/octet-stream',
    );
    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).error.code, 'storage_permission_denied');
    expect(result.error.message, contains('صلاحية'));
  });

  test('غياب المنصة لا يُسقط التطبيق', () async {
    mock((call) async => throw MissingPluginException('no plugin'));
    final result = await VisibleStorageBridge().saveToDownloads(
      bytes: bytes,
      fileName: 'backup.krt',
      mimeType: 'application/octet-stream',
    );
    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).error.code, 'storage_unsupported');
  });
}
