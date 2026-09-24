import 'package:flutter/services.dart';

/// حالة خدمة الحفاظ على التسليم كما تعرفها الطبقة الأصلية.
final class DeliveryKeepAliveStatus {
  const DeliveryKeepAliveStatus({
    required this.active,
    required this.smsPermissionsGranted,
  });

  /// الخدمة الأمامية تعمل الآن (العملية محميّة من التجميد/القتل).
  final bool active;

  /// صلاحية قراءة وإرسال SMS — شرط عمل الخدمة.
  final bool smsPermissionsGranted;

  static const inactive = DeliveryKeepAliveStatus(
    active: false,
    smsPermissionsGranted: false,
  );

  static DeliveryKeepAliveStatus fromPlatform(Object? raw) {
    if (raw is! Map) return inactive;
    final map = Map<String, dynamic>.from(raw);
    return DeliveryKeepAliveStatus(
      active: map['active'] == true || map['active'] == 'true',
      smsPermissionsGranted: map['smsPermissionsGranted'] == true ||
          map['smsPermissionsGranted'] == 'true',
    );
  }
}

/// جسر خدمة `DeliveryKeepAliveService` على أندرويد.
///
/// الواجهة تطلب تشغيل الخدمة، والقرار النهائي (تشغيل/إيقاف/لا شيء) في
/// `DeliveryKeepAlivePolicy` داخل الطبقة الأصلية. على أي منصّة أخرى — أو في
/// الاختبارات — يُرجَع `inactive` بلا استثناء.
final class DeliveryKeepAliveBridge {
  DeliveryKeepAliveBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kayan.net/keepalive');

  final MethodChannel _channel;

  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stop') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<DeliveryKeepAliveStatus> status() async {
    try {
      return DeliveryKeepAliveStatus.fromPlatform(
        await _channel.invokeMethod<dynamic>('status'),
      );
    } catch (_) {
      return DeliveryKeepAliveStatus.inactive;
    }
  }
}
