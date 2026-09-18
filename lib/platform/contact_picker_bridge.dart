import 'package:flutter/services.dart';

import '../domain/phone_normalizer.dart';

/// جسر اختيار جهة اتصال من دفتر هاتف الجهاز — عرض/إدخال فقط.
///
/// لا يعدل أي بيانات: يعيد رقمًا صريحًا لاختيار المستخدم ليُدرج في الحقل
/// الهدف، ويتعامل مع غياب المنصة (اختبارات) بإرجاع null بهدوء.
final class ContactPickerBridge {
  ContactPickerBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kayan.net/diagnostics');

  final MethodChannel _channel;

  /// صلاحية قراءة جهات الاتصال الحالية.
  Future<bool> hasContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasContactsPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// يطلب صلاحية قراءة جهات الاتصال عند الحاجة.
  Future<bool> requestContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestContacts') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// يفتح منتقي جهات الاتصال ويعيد الرقم المختار (كانونيًا) أو null.
  ///
  /// الطلب التلقائي للصلاحية يتم هنا حتى لا يعرف أي شاشة تفاصيل المنصة.
  Future<String?> pickPhone() async {
    final granted = await hasContactsPermission();
    if (!granted) {
      final requested = await requestContactsPermission();
      if (!requested) return null;
    }
    try {
      final raw = await _channel.invokeMethod<String?>('pickContact');
      if (raw == null || raw.trim().isEmpty) return null;
      return PhoneNormalizer.canonicalize(raw) ?? raw.trim();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
