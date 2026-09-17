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
}
