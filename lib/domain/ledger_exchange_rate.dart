import 'dart:convert';

import 'customer_file_currency.dart';

/// سعر صرف للعرض فقط. لا يعيد كتابة الدفتر ولا يحوّل الحركات التاريخية.
final class LedgerExchangeRate {
  const LedgerExchangeRate._();

  /// وحدات صغرى من الريال اليمني مقابل وحدة كبرى واحدة من العملة الأجنبية.
  static const yerMinorPerMajor = 100;

  static Map<String, int> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, int>{};
      decoded.forEach((key, value) {
        final code = normalizeCode(key?.toString());
        final rate = normalizeRate(value);
        if (code == null || rate == null) return;
        out[code] = rate;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String? normalizeCode(String? raw) {
    final code = raw?.trim().toUpperCase() ?? '';
    if (code.isEmpty || code == CustomerFileCurrency.defaultCode) return null;
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return null;
    return code;
  }

  static int? normalizeRate(Object? raw) {
    final rate = switch (raw) {
      int value => value,
      num value => value.round(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (rate == null || rate <= 0 || rate > 100000000) return null;
    return rate;
  }

  static int? lookup(String? raw, String currencyCode) {
    final code = normalizeCode(currencyCode);
    if (code == null) return null;
    return decodeMap(raw)[code];
  }

  static String encodeMap(
    String? raw, {
    required String currencyCode,
    required int? ratePerMajor,
  }) {
    final next = Map<String, int>.from(decodeMap(raw));
    final code = normalizeCode(currencyCode);
    if (code == null) return jsonEncode(next);
    final rate = normalizeRate(ratePerMajor);
    if (rate == null) {
      next.remove(code);
    } else {
      next[code] = rate;
    }
    return jsonEncode(next);
  }

  /// يحوّل مبلغًا بين عملتين عبر الريال. يعيد null إذا نقص سعر لازم.
  static int? convertMinor({
    required int minorUnits,
    required String from,
    required String to,
    required Map<String, int> rates,
  }) {
    final source = from.trim().toUpperCase();
    final target = to.trim().toUpperCase();
    if (source == target) return minorUnits;
    final yer = _toYerMinor(minorUnits, source, rates);
    if (yer == null) return null;
    return _fromYerMinor(yer, target, rates);
  }

  static int? _toYerMinor(int minorUnits, String code, Map<String, int> rates) {
    if (code == CustomerFileCurrency.defaultCode) return minorUnits;
    final rate = rates[code];
    if (rate == null) return null;
    return (minorUnits * rate) ~/ yerMinorPerMajor;
  }

  static int? _fromYerMinor(
    int yerMinor,
    String code,
    Map<String, int> rates,
  ) {
    if (code == CustomerFileCurrency.defaultCode) return yerMinor;
    final rate = rates[code];
    if (rate == null) return null;
    return (yerMinor * yerMinorPerMajor) ~/ rate;
  }

  /// تقدير عرض لمجموع عملات مكتملة. العملة بلا سعر تُستبعد ولا تُخلط.
  static ExchangeQuote quote({
    required Map<String, int> balancesByCurrency,
    required String targetCurrency,
    required Map<String, int> rates,
  }) {
    final target = targetCurrency.trim().toUpperCase().isEmpty
        ? CustomerFileCurrency.defaultCode
        : targetCurrency.trim().toUpperCase();
    var total = 0;
    final missing = <String>[];
    final keys = balancesByCurrency.keys.toList()..sort();
    for (final code in keys) {
      final converted = convertMinor(
        minorUnits: balancesByCurrency[code] ?? 0,
        from: code,
        to: target,
        rates: rates,
      );
      if (converted == null) {
        missing.add(code);
        continue;
      }
      total += converted;
    }
    return ExchangeQuote(
      targetCurrency: target,
      minorUnits: total,
      missingCurrencies: missing,
    );
  }

  /// تقدير مدين/دائن لكل العملات. العملة بلا سعر تُستبعد من الجانبين ولا تُخلط.
  static ExchangeSideQuote quoteSides({
    required Map<String, int> debtorByCurrency,
    required Map<String, int> creditorByCurrency,
    required String targetCurrency,
    required Map<String, int> rates,
  }) {
    final debtor = quote(
      balancesByCurrency: debtorByCurrency,
      targetCurrency: targetCurrency,
      rates: rates,
    );
    final creditor = quote(
      balancesByCurrency: creditorByCurrency,
      targetCurrency: targetCurrency,
      rates: rates,
    );
    final missing = {...debtor.missingCurrencies, ...creditor.missingCurrencies}.toList()
      ..sort();
    return ExchangeSideQuote(
      targetCurrency: debtor.targetCurrency,
      debtorMinorUnits: debtor.minorUnits,
      creditorMinorUnits: creditor.minorUnits,
      missingCurrencies: missing,
    );
  }
}


final class ExchangeQuote {
  const ExchangeQuote({
    required this.targetCurrency,
    required this.minorUnits,
    required this.missingCurrencies,
  });

  final String targetCurrency;
  final int minorUnits;
  final List<String> missingCurrencies;

  bool get complete => missingCurrencies.isEmpty;
}

final class ExchangeSideQuote {
  const ExchangeSideQuote({
    required this.targetCurrency,
    required this.debtorMinorUnits,
    required this.creditorMinorUnits,
    required this.missingCurrencies,
  });

  final String targetCurrency;
  final int debtorMinorUnits;
  final int creditorMinorUnits;
  final List<String> missingCurrencies;

  bool get complete => missingCurrencies.isEmpty;
}
