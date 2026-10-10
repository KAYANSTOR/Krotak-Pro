import 'dart:convert';

/// سقف سلفني لكل عميل، مخزّن في الإعدادات حتى لا يحتاج عمود قاعدة جديد.
///
/// الغياب يعني بلا سقف فردي. الصفر يمنع أي صرف. القيمة الموجبة وحدات صغرى
/// ولا يجوز أن تتجاوزها قيمة الفئة المصروفة.
abstract final class SalafniCustomerCeiling {
  static const key = 'salafni_customer_ceiling_v1';

  static Map<String, int> decode(String? raw) {
    // خريطة قابلة للتعديل: ملف العميل يعدّل النسخة المفكوكة قبل حفظها،
    // وإرجاع خريطة ثابتة يجعل أول تعيين لسقف عميل يفشل.
    if (raw == null || raw.trim().isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final out = <String, int>{};
      for (final entry in decoded.entries) {
        final id = entry.key.toString().trim();
        final value = entry.value;
        final minor = value is int
            ? value
            : value is num
                ? value.round()
                : int.tryParse(value.toString());
        if (id.isEmpty || minor == null || minor < 0) continue;
        out[id] = minor;
      }
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }

  static String encode(Map<String, int> ceilings) {
    final clean = <String, int>{};
    for (final entry in ceilings.entries) {
      final id = entry.key.trim();
      if (id.isEmpty || entry.value < 0) continue;
      clean[id] = entry.value;
    }
    return jsonEncode(clean);
  }

  /// `null` بلا سقف. غير ذلك الحد الأقصى بالوحدات الصغرى شاملًا الصفر.
  static int? forCustomer(String? raw, String customerId) {
    final id = customerId.trim();
    if (id.isEmpty) return null;
    final map = decode(raw);
    return map.containsKey(id) ? map[id] : null;
  }
}
