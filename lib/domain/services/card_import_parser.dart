import 'services.dart';

/// Parses pasted/imported card lines into [CardImportDraft]s.
///
/// Supported line formats (one card per line):
/// - `serial,secret`
/// - `serial;secret`
/// - `serial\tsecret`
/// - `serial secret` (whitespace)
///
/// Blank lines and lines starting with `#` are skipped.
/// Returns both accepted drafts and per-line error messages (1-based).
final class CardImportParseResult {
  const CardImportParseResult({
    required this.drafts,
    required this.errors,
  });

  final List<CardImportDraft> drafts;
  final List<String> errors;

  bool get hasDrafts => drafts.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
}

abstract final class CardImportParser {
  static final _sep = RegExp(r'[,;\t]| {2,}');

  static CardImportParseResult parse(String raw) {
    final drafts = <CardImportDraft>[];
    final errors = <String>[];
    final seen = <String>{};
    final seenSecrets = <String>{};
    final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      var line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Strip optional CSV header
      if (lineNo == 1 &&
          (line.toLowerCase().contains('serial') ||
              line.contains('تسلسل') ||
              line.toLowerCase().contains('pin') ||
              line.contains('رمز'))) {
        continue;
      }

      final parts = line.split(_sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length < 2) {
        final space = line.split(RegExp(r'\s+'));
        if (space.length >= 2) {
          parts
            ..clear()
            ..addAll([space.first, space.sublist(1).join(' ')]);
        }
      }
      if (parts.length < 2) {
        errors.add('سطر $lineNo: يُتوقَّع رقم تسلسلي ورمز سري');
        continue;
      }

      final serial = parts[0];
      final secret = parts[1];
      if (serial.isEmpty || secret.isEmpty) {
        errors.add('سطر $lineNo: حقول فارغة');
        continue;
      }
      if (seen.contains(serial)) {
        errors.add('سطر $lineNo: تكرار الرقم التسلسلي $serial');
        continue;
      }
      if (seenSecrets.contains(secret)) {
        errors.add('سطر $lineNo: تكرار الرمز السري');
        continue;
      }
      seen.add(serial);
      seenSecrets.add(secret);
      drafts.add(CardImportDraft(serialNumber: serial, secretCode: secret));
    }

    return CardImportParseResult(drafts: drafts, errors: errors);
  }
}
