import 'package:flutter/widgets.dart';

import '../platform/delivery_keep_alive_bridge.dart';

/// قرار تشغيل خدمة الحفاظ على تسليم الكروت في الخلفية.
///
/// حلقة التسليم (مؤقّت كل 3 ثوانٍ) تعمل داخل عملية التطبيق، وأندرويد يجمّد
/// التطبيقات المخزّنة ثم يقتل العملية — فتتوقف قسيمة العميل بعد بيع مُلتزم.
/// هذه الطبقة تُطلب الخدمة الأمامية في الوقت الصحيح، ولا تُوقفها أبدًا عند
/// انتقال الواجهة إلى الخلفية.
final class DeliveryKeepAliveController {
  DeliveryKeepAliveController({required DeliveryKeepAliveBridge bridge})
      : _bridge = bridge;

  final DeliveryKeepAliveBridge _bridge;

  DeliveryKeepAliveStatus _status = DeliveryKeepAliveStatus.inactive;
  DeliveryKeepAliveStatus get status => _status;

  /// هل العملية محميّة من التجميد/القتل الآن (حسب الطبقة الأصلية).
  bool get backgroundDeliveryActive => _status.active;

  /// عدد طلبات المزامنة المنفّذة — يُستخدم في الاختبارات والأثر التشغيلي.
  int get syncCount => _syncCount;
  int _syncCount = 0;

  /// تُستدعى عند الإقلاع، وعند كل عودة للواجهة، وبعد أي تغيّر في صلاحية SMS.
  ///
  /// بلا صلاحية SMS لا معنى لإشعار دائم: نوقف الخدمة صراحةً. ومع الصلاحية
  /// نطلب التشغيل (والقرار النهائي في `DeliveryKeepAlivePolicy`).
  Future<DeliveryKeepAliveStatus> sync({required bool smsPermissionsGranted}) async {
    _syncCount++;
    if (smsPermissionsGranted) {
      await _bridge.start();
    } else {
      await _bridge.stop();
    }
    _status = await _bridge.status();
    return _status;
  }

  /// تعامل دورة حياة الواجهة مع الخدمة.
  ///
  /// يُعاد تأكيد الطلب عند العودة إلى المقدمة فقط (قد تكون الخدمة قُتلت مع
  /// العملية أو لم تُشغَّل بعد)، أما الخلفية فتُترك كما هي: لا إيقاف.
  Future<DeliveryKeepAliveStatus> handleLifecycle(
    AppLifecycleState state, {
    required bool smsPermissionsGranted,
  }) {
    if (!shouldReassertOnLifecycle(state)) return Future.value(_status);
    return sync(smsPermissionsGranted: smsPermissionsGranted);
  }

  /// الموضع الوحيد الذي نطلب فيه التشغيل: الواجهة في المقدمة.
  static bool shouldReassertOnLifecycle(AppLifecycleState state) =>
      state == AppLifecycleState.resumed;
}
