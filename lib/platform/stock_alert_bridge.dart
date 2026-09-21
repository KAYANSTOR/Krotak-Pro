import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/services/services.dart';

/// ينفّذ إشعار المخزون الحي على أندرويد عبر القناة الأصلية
/// `com.kayan.net/alerts`.
///
/// الإشعار من نوع «مستمر» (ongoing): لا يُسحب ولا يُغلق من المستخدم، ويبقى في
/// شريط الإشعارات حتى يُلغى من هنا بعد إعادة تعبئة المخزون فوق العتبة.
///
/// كل الأخطاء مكتومة عمداً: فشل عرض إشعار لا يجوز أن يُسقط أي عملية مخزون أو
/// بيع، كما أن هذا الجسر غير موجود في الاختبارات وبيئات غير أندرويد.
final class NativeStockAlertNotifier implements StockAlertNotifier {
  NativeStockAlertNotifier({MethodChannel? methods})
      : _methods = methods ?? const MethodChannel('com.kayan.net/alerts');

  final MethodChannel _methods;

  @override
  Future<void> show({required String title, required String body}) async {
    if (title.trim().isEmpty || body.trim().isEmpty) return;
    try {
      await _methods.invokeMethod<void>('showStockAlert', {
        'title': title,
        'body': body,
      });
    } catch (error) {
      debugPrint('stock alert show failed: $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _methods.invokeMethod<void>('clearStockAlert');
    } catch (error) {
      debugPrint('stock alert clear failed: $error');
    }
  }

  /// هل إشعارات التطبيق مسموحة على الجهاز (إذن أندرويد 13+ + مفتاح النظام)؟
  Future<bool> hasPermission() async {
    try {
      return await _methods.invokeMethod<bool>('hasNotificationPermission') ?? false;
    } catch (error) {
      debugPrint('stock alert permission probe failed: $error');
      return false;
    }
  }

  /// يطلب إذن الإشعارات (يظهر لمرة واحدة على أندرويد 13+).
  Future<bool> requestPermission() async {
    try {
      return await _methods.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } catch (error) {
      debugPrint('stock alert permission request failed: $error');
      return false;
    }
  }
}
