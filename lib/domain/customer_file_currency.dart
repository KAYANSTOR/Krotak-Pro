import 'entities/transaction.dart';

/// عملة عرض ملف العميل. لا تعيد كتابة الدفتر ولا تحوّل الحركات التاريخية.
final class CustomerFileCurrency {
  const CustomerFileCurrency._();

  static const defaultCode = 'YER';

  static List<String> availableCodes(Iterable<Transaction> transactions) {
    final codes = <String>{defaultCode};
    for (final tx in transactions) {
      final code = tx.amount.currencyCode.trim();
      if (code.isNotEmpty) codes.add(code);
    }
    final list = codes.toList()
      ..sort((a, b) {
        if (a == defaultCode) return -1;
        if (b == defaultCode) return 1;
        return a.compareTo(b);
      });
    return list;
  }

  static String keepOrDefault(String selected, Iterable<String> available) {
    final code = selected.trim();
    if (code.isNotEmpty && available.contains(code)) return code;
    return defaultCode;
  }

  static List<Transaction> rowsFor(
    Iterable<Transaction> transactions,
    String currencyCode,
  ) {
    final code = currencyCode.trim().isEmpty ? defaultCode : currencyCode.trim();
    return [
      for (final tx in transactions)
        if (tx.amount.currencyCode == code) tx,
    ];
  }

  static String label(String currencyCode) =>
      currencyCode == defaultCode ? 'ر.ي' : currencyCode;
}
