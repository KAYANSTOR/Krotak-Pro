/// Classifies the canonical inbound POS card-order command before financial processing.
abstract final class PosOrderMessageClassifier {
  static bool isCardOrder(String raw) {
    var normalized = raw
        .trim()
        .replaceAll(
          RegExp(r'[\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]'),
          '',
        );
    normalized = _normalizeDigits(normalized)
        .replaceAll('كروت', 'كرت')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();

    return RegExp(
      r'^\\d{1,2}\\s+كرت\\s+\\d+(?:[.,]\\d{1,2})?(?:\\s+\\+?\\d{7,15})?$',
      unicode: true,
    ).hasMatch(normalized);
  }

  static String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      final p = persian.indexOf(ch);
      if (e >= 0) {
        out.write(e);
      } else if (p >= 0) {
        out.write(p);
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }
}
