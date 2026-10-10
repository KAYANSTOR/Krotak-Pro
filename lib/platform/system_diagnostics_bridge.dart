import 'package:flutter/services.dart';

/// جسر فحص جاهزية أندرويد — صلاحيات SMS، إشعارات، بطارية، شرائح، جهات اتصال.
final class SystemDiagnosticsBridge {
  SystemDiagnosticsBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kayan.net/diagnostics');

  final MethodChannel _channel;

  Future<Map<String, dynamic>> probe() async {
    try {
      final raw = await _channel.invokeMethod<Map>('probe');
      if (raw == null) return const {};
      return Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return const {'platform': 'unsupported'};
    } on PlatformException {
      return const {'platform': 'error'};
    }
  }

  Future<bool> requestSmsPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestSmsPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestContacts') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasContactsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationAccess() async {
    try {
      await _channel.invokeMethod<void>('openNotificationAccess');
    } catch (_) {}
  }

  Future<void> openBatteryOptimization() async {
    try {
      await _channel.invokeMethod<void>('openBatteryOptimization');
    } catch (_) {}
  }

  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  Future<void> openAutoStartSettings() async {
    try {
      await _channel.invokeMethod<void>('openAutoStartSettings');
    } catch (_) {}
  }

  Future<void> confirmAutoStartReviewed() async {
    try {
      await _channel.invokeMethod<void>('confirmAutoStartReviewed');
    } catch (_) {}
  }

  Future<void> scheduleDailySummary() async {
    try {
      await _channel.invokeMethod<void>('scheduleDailySummary');
    } catch (_) {}
  }

  Future<void> cancelDailySummary() async {
    try {
      await _channel.invokeMethod<void>('cancelDailySummary');
    } catch (_) {}
  }

  /// WP-9 — أسباب إنهاء العملية من النظام (Android 11+).
  ///
  /// تُرجع أرماز مستقرة فقط؛ النص العربي يُبنى في
  /// `BackgroundDiagnostics` ليُختبر محليًا.
  Future<List<Object?>> exitReasons() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('exitReasons');
      return raw ?? const <Object?>[];
    } catch (_) {
      return const <Object?>[];
    }
  }

  /// WP-9 — سجل أحداث خدمة الحفاظ (بدء/رفض/مهلة/إعادة تشغيل).
  Future<List<Object?>> keepAliveEvents() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('keepAliveEvents');
      return raw ?? const <Object?>[];
    } catch (_) {
      return const <Object?>[];
    }
  }

  /// مستوى الاستهداف الفعلي من التطبيق (يحدّد سلوك الخدمة الأمامية).
  Future<int?> targetSdk() async {
    try {
      return await _channel.invokeMethod<int>('targetSdk');
    } catch (_) {
      return null;
    }
  }
}

