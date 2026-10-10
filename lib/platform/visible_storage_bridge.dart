import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/result.dart';
import '../domain/services/visible_storage_service.dart';

/// WP-S1 — الجسر الفعلي إلى قناة `com.kayan.net/storage`.
///
/// القناة تُرجع خريطة `{'path': '<المسار الفعلي>', 'uri': '<content://…>'}`
/// أو خطأ برمز مفهوم. أي `MissingPluginException` (تشغيل على غير أندرويد أو
/// اختبار بلا محاكاة) يُترجم إلى فشل عربي مفهوم لا إلى انهيار.
final class VisibleStorageBridge implements VisibleStorageService {
  VisibleStorageBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kayan.net/storage');

  final MethodChannel _channel;

  @override
  Future<Result<String>> saveToDownloads({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String subfolder = '',
  }) {
    return _invoke('saveToDownloads', {
      'bytes': bytes,
      'fileName': fileName,
      'mimeType': mimeType,
      'subfolder': subfolder,
    });
  }

  @override
  Future<Result<String>> saveImageToPictures({
    required Uint8List bytes,
    required String fileName,
    String subfolder = '',
  }) {
    return _invoke('saveImageToPictures', {
      'bytes': bytes,
      'fileName': fileName,
      'subfolder': subfolder,
    });
  }

  Future<Result<String>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Map>(method, arguments);
      return _fromRaw(raw);
    } on MissingPluginException {
      return const Failure(
        AppFailure(
          code: 'storage_unsupported',
          message: 'تعذر الوصول إلى تخزين الملفات على هذا الجهاز.',
        ),
      );
    } on PlatformException catch (error) {
      return Failure(_failureFrom(error));
    } catch (_) {
      return const Failure(
        AppFailure(
          code: 'storage_failed',
          message: 'تعذر حفظ الملف. حاول مرة أخرى.',
        ),
      );
    }
  }

  Result<String> _fromRaw(Map? raw) {
    final path = (raw?['path'] ?? raw?['uri'])?.toString();
    if (path == null || path.trim().isEmpty) {
      return const Failure(
        AppFailure(
          code: 'storage_failed',
          message: 'تعذر حفظ الملف. حاول مرة أخرى.',
        ),
      );
    }
    return Success(path);
  }

  AppFailure _failureFrom(PlatformException error) {
    switch (error.code) {
      case 'storage_permission_denied':
        return const AppFailure(
          code: 'storage_permission_denied',
          message: 'صلاحية التخزين مرفوضة. امنح التطبيق صلاحية حفظ الملفات.',
        );
      case 'storage_unsupported':
        return const AppFailure(
          code: 'storage_unsupported',
          message: 'تعذر الوصول إلى تخزين الملفات على هذا الجهاز.',
        );
      default:
        return const AppFailure(
          code: 'storage_failed',
          message: 'تعذر حفظ الملف. حاول مرة أخرى.',
        );
    }
  }
}
