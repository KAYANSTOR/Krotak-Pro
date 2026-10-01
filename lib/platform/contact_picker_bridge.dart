import 'package:flutter/services.dart';

import '../core/result.dart';
import '../domain/phone_normalizer.dart';
import '../domain/services/contact_directory.dart';

/// جسر جهات الاتصال: اختيار يدوي + بحث بالرقم لمسار الإيداع التلقائي.
final class ContactPickerBridge implements ContactDirectory, ContactWriter {
  ContactPickerBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kayan.net/diagnostics');

  final MethodChannel _channel;

  Future<bool> hasContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasContactsPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestContacts') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<DeviceContactMatch?> findByPhone(String phone) => lookupByPhone(phone);

  @override
  Future<Result<void>> upsertPhone({
    required String phone,
    required String displayName,
  }) async {
    final rawPhone = phone.trim();
    if (rawPhone.isEmpty) {
      return const Failure(
        AppFailure(code: 'invalid_contact_phone', message: 'رقم جهة الاتصال غير صالح'),
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>('upsertContactByPhone', {
        'phone': rawPhone,
        'displayName': displayName.trim().isEmpty ? rawPhone : displayName.trim(),
      }) ?? false;
      if (ok) return const Success(null);
      return const Failure(
        AppFailure(code: 'contact_write_denied', message: 'تعذرت إضافة الرقم إلى جهات الاتصال'),
      );
    } on MissingPluginException {
      return const Failure(
        AppFailure(code: 'contact_write_unavailable', message: 'إضافة جهات الاتصال غير متاحة على هذا الجهاز'),
      );
    } on PlatformException catch (e) {
      return Failure(
        AppFailure(code: e.code.isEmpty ? 'contact_write_failed' : e.code, message: e.message ?? 'تعذرت إضافة جهة الاتصال'),
      );
    }
  }

  /// يبحث عن [phone] في دفتر جهات الاتصال (مسار خلفي بلا UI).
  /// لا يطلب الصلاحية تفاعلياً — إن لم تكن ممنوحة يُعاد null (دفتر مؤقت).
  Future<DeviceContactMatch?> lookupByPhone(String phone) async {
    final raw = phone.trim();
    if (raw.isEmpty) return null;
    final granted = await hasContactsPermission();
    if (!granted) return null;
    try {
      final keys = PhoneNormalizer.lookupKeys(raw);
      for (final key in keys) {
        final map = await _channel.invokeMethod<dynamic>('lookupContactByPhone', {
          'phone': key,
        });
        if (map is Map) {
          final name = (map['displayName'] as String?)?.trim() ?? '';
          final num = (map['phone'] as String?)?.trim() ?? raw;
          if (name.isNotEmpty) {
            return DeviceContactMatch(displayName: name, phone: num);
          }
        }
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// يفتح منتقي جهات الاتصال ويعيد الرقم المختار (كانونياً) أو null.
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
