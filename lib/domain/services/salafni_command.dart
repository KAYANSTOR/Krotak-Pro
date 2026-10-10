/// تحليل أمر سلفني الوارد من رسالة أو إدخال يدوي.
///
/// الصيغ المقبولة: `سلفني` و`س` و`s` و`salafni`، مع مبلغ اختياري
/// بالأرقام اللاتينية أو العربية/الفارسية. المبلغ وحدة كبرى (ريال)
/// ويُحوَّل إلى وحدات صغرى بضرب 100. لا يُقبل نص زائد بعد المبلغ.
abstract final class SalafniCommand {
  static const _easternDigits = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  /// `null` إذا لم يكن النص أمر سلفني. المبلغ `null` يعني الأمر العام بلا فئة.
  static SalafniCommandParse? tryParse(String raw) {
    var text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    text = text.replaceAll(RegExp('[\u200e\u200f\u202a-\u202e]'), '');
    final western = StringBuffer();
    for (final ch in text.split('')) {
      western.write(_easternDigits[ch] ?? ch);
    }
    text = western.toString().trim();
    final match = RegExp(
      r'^(سلفني|salafni|س|s)(?:\s+(\d+(?:\.\d{1,2})?))?\s*$',
    ).firstMatch(text);
    if (match == null) return null;
    final amountRaw = match.group(2);
    if (amountRaw == null) {
      return const SalafniCommandParse();
    }
    final major = double.tryParse(amountRaw);
    if (major == null || major <= 0) return null;
    final minor = (major * 100).round();
    if (minor <= 0) return null;
    return SalafniCommandParse(amountMinorUnits: minor);
  }
}

final class SalafniCommandParse {
  const SalafniCommandParse({this.amountMinorUnits});

  /// قيمة الفئة المطلوبة بالوحدات الصغرى، أو `null` للأمر بلا مبلغ.
  final int? amountMinorUnits;
}
