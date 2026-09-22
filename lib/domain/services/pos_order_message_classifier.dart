/// Classifies canonical inbound POS card-order commands before financial processing.
abstract final class PosOrderMessageClassifier {
  static bool isCardOrder(String raw) {
    final normalized = _normalizeDigits(raw.trim())
        .replaceAll('كروت', 'كرت')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (normalized.length != 3 && normalized.length != 4) return false;
    if (normalized[1] != 'كرت') return false;

    final quantity = int.tryParse(normalized[0]);
    if (quantity == null || quantity < 1 || quantity > 20) return false;

    final category = double.tryParse(normalized[2].replaceAll(',', '.'));
    if (category == null || category <= 0) return false;

    if (normalized.length == 4) {
      final phone = normalized[3];
      final digits = phone.startsWith('+') ? phone.substring(1) : phone;
      if (digits.length < 7 || digits.length > 15) return false;
      if (!RegExp(r'^\d{7,15}
    }

    return true;
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
).hasMatch(digits)) return false;
    }

    return true;
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
