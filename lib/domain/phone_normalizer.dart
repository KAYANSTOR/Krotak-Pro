/// Canonical phone identity for Yemen-centric + E.164-style inputs.
///
/// Phase 1 Identity Engine (Post-V1 Master Plan):
/// store and look up a single representation so these match the same customer:
///
/// ```text
/// 0777123456
/// +967777123456
/// 00967777123456
/// 777123456
///         ↓
/// 777123456
/// ```
///
/// Non-phone tokens are left unchanged by [forStorage] when [isPhone] is false.
abstract final class PhoneNormalizer {
  static final RegExp _nonDigit = RegExp(r'\D');

  /// خرائط الأرقام العربية-الهندية والفارسية إلى لاتينية قبل استخراج الأرقام.
  static const Map<String, String> _easternDigits = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  /// يحوّل الأرقام الشرقية إلى لاتينية دون حذف باقي المحارف.
  static String toWesternDigits(String raw) {
    if (raw.isEmpty) return raw;
    final buf = StringBuffer();
    for (final ch in raw.split('')) {
      buf.write(_easternDigits[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Digits only (بعد تطبيع الأرقام الشرقية)، بدون علامات.
  static String digitsOnly(String raw) =>
      toWesternDigits(raw).replaceAll(_nonDigit, '');

  /// True when the value is plausibly a phone number (not account/name).
  static bool isPhoneLike(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('+')) {
      final rest = digitsOnly(t);
      return rest.length >= 7 && rest.length <= 15;
    }
    final digits = digitsOnly(t);
    return digits.length >= 7 && digits.length <= 15;
  }

  /// Canonical local mobile form used as the identity key.
  ///
  /// Yemen (`967`): strip country code and leading trunk `0`, keep national
  /// number (typically 9 digits starting with `7`).
  ///
  /// Other country codes: return digits without a leading `00` international
  /// prefix when present; does not invent a local form for unknown countries.
  static String? canonicalize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    var digits = digitsOnly(t);
    if (digits.length < 7 || digits.length > 15) return null;

    // 00 prefix → international
    if (digits.startsWith('00') && digits.length > 4) {
      digits = digits.substring(2);
    }

    // Yemen country code
    if (digits.startsWith('967') && digits.length >= 12) {
      digits = digits.substring(3);
    }

    // National trunk zero (e.g. 0777…)
    if (digits.startsWith('0') && digits.length >= 8) {
      digits = digits.substring(1);
    }

    if (digits.length < 7 || digits.length > 12) return null;
    return digits;
  }

  /// Value to persist for phone identifiers (canonical or trimmed fallback).
  static String forStorage(String raw, {required bool asPhone}) {
    final t = raw.trim();
    if (!asPhone) return t;
    return canonicalize(t) ?? t;
  }

  /// Ordered unique keys to try when looking up an identifier in storage.
  ///
  /// Includes the raw trim, canonical form, and common written variants so
  /// legacy rows stored before normalization still resolve.
  static List<String> lookupKeys(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];

    final keys = <String>{};
    keys.add(t);

    final canonical = canonicalize(t);
    if (canonical != null) {
      keys.add(canonical);
      keys.add('0$canonical');
      keys.add('967$canonical');
      keys.add('+967$canonical');
      keys.add('00967$canonical');
    }

    final digits = digitsOnly(t);
    if (digits.isNotEmpty) keys.add(digits);

    return keys.toList(growable: false);
  }

  /// Whether two raw values refer to the same phone identity.
  static bool samePhone(String a, String b) {
    final ca = canonicalize(a);
    final cb = canonicalize(b);
    if (ca != null && cb != null) return ca == cb;
    return a.trim() == b.trim();
  }
}
