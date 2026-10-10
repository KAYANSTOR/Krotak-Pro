import 'dart:convert';

/// حظر استقبال إيداعات عميل دون تغيير حالته أو منعه من البيع وسلفني.
///
/// الغياب يعني الإيداع مسموح. الوجود في الخريطة يعني الرفض قبل أي قيد.
abstract final class CustomerDepositBlock {
  static const key = 'customer_deposits_blocked_v1';

  static Set<String> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static String encode(Set<String> blocked) {
    final ids = blocked.map((id) => id.trim()).where((id) => id.isNotEmpty).toList()
      ..sort();
    return jsonEncode(ids);
  }

  static bool isBlocked(String? raw, String customerId) {
    final id = customerId.trim();
    if (id.isEmpty) return false;
    return decode(raw).contains(id);
  }
}
