/// إعادة تشغيل داخلية للتطبيق دون إغلاقه: تُغلق الحاوية الحالية (وقاعدة
/// البيانات) وتُنشئ حاوية جديدة وتعيد بناء كل الشاشات من الصفر.
///
/// يسجّل `NetApp` معالجه عند الإقلاع؛ تستدعيه شاشات مثل «استعادة نسخة
/// احتياطية» بعد استبدال ملف قاعدة البيانات، فتظهر البيانات المستعادة فوراً.
abstract final class AppReloader {
  static Object? _owner;
  static Future<void> Function()? _handler;
  static String? _pendingNotice;

  static bool get isAvailable => _handler != null;

  static void register(Object owner, Future<void> Function() handler) {
    _owner = owner;
    _handler = handler;
  }

  static void unregister(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _handler = null;
    }
  }

  /// رسالة تُعرض مرة واحدة على الشاشة الرئيسية بعد إعادة التحميل.
  static void setNotice(String message) => _pendingNotice = message;

  static String? takeNotice() {
    final value = _pendingNotice;
    _pendingNotice = null;
    return value;
  }

  /// يعيد تحميل التطبيق. لا يفعل شيئاً (ويعيد false) إن لم يكن هناك معالج.
  static Future<bool> reload() async {
    final handler = _handler;
    if (handler == null) return false;
    await handler();
    return true;
  }
}
