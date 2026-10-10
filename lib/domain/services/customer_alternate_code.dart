/// كود بديل للعميل: نص أو رقم أو مزيج، بطول 4 إلى 15، فريد عالميًا.
///
/// يُخزَّن كمعرّف `externalReference` حتى يطابق الإيداع نفس مسار البحث.
/// التفرد عالمي لأن فهرس المعرّفات فريد على القيمة، ولا يُربط بمحفظة.
abstract final class CustomerAlternateCode {
  static final RegExp _allowed = RegExp(r'^[0-9A-Za-z\u0600-\u06FF]{4,15}$');

  /// `null` إذا كان الطول أو المحارف غير مقبولة. اللاتيني يُحفظ بحروف كبيرة.
  static String? normalize(String raw) {
    final trimmed = raw.trim();
    if (!_allowed.hasMatch(trimmed)) return null;
    return trimmed.toUpperCase();
  }
}
