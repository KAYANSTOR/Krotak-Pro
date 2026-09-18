import 'services.dart';

/// Parses pasted/imported card lines into [CardImportDraft]s.
///
/// Supported line formats (one card per line):
/// - `serial,secret` / `serial;secret` / `serial\tsecret` / `serial secret`
/// - `serial` alone when [CardImportFormat.serialOnly]
///
/// Blank lines and lines starting with `#` are skipped.
final class CardImportParseResult {
  const CardImportParseResult({
    required this.drafts,
    required this.errors,
    required this.format,
  });

  final List<CardImportDraft> drafts;
  final List<String> errors;
  final CardImportFormat format;

  bool get hasDrafts => drafts.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
}

abstract final class CardImportParser {
  static final _fieldSeparator = RegExp(r'[,;\t]+');
  static final _whitespaceSeparator = RegExp(r'\s+');

  static CardImportParseResult parse(
    String raw, {
    CardImportFormat format = CardImportFormat.serialAndPin,
  }) {
    final drafts = <CardImportDraft>[];
    final errors = <String>[];
    final seen = <String>{};
    final lines =
        raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final lower = line.toLowerCase();
      final looksLikeHeader =
          (lower.contains('serial') &&
              (lower.contains('pin') || lower.contains('secret'))) ||
          (line.contains('تسلسل') &&
              (line.contains('رمز') || line.contains('سري'))) ||
          (lineNo == 1 &&
              (lower == 'serial' ||
                  lower == 'رقم' ||
                  lower.contains('رقم الكرت')));
      if (lineNo == 1 && looksLikeHeader) continue;

      if (format == CardImportFormat.serialOnly) {
        var serial = line;
        final delimited = line
            .split(_fieldSeparator)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        if (delimited.isNotEmpty) serial = delimited.first;
        serial = serial.trim();
        if (serial.isEmpty) {
          errors.add('سطر $lineNo: رقم كرت فارغ');
          continue;
        }
        if (seen.contains(serial)) {
          errors.add('سطر $lineNo: تكرار رقم الكرت $serial');
          continue;
        }
        seen.add(serial);
        drafts.add(
          CardImportDraft(
            serialNumber: serial,
            secretCode: '',
            format: CardImportFormat.serialOnly,
          ),
        );
        continue;
      }

      List<String> parts = line
          .split(_fieldSeparator)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);

      if (parts.length < 2) {
        final whitespaceParts = line
            .split(_whitespaceSeparator)
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        if (whitespaceParts.length >= 2) {
          parts = <String>[
            whitespaceParts.first,
            whitespaceParts.sublist(1).join(' '),
          ];
        }
      }

      if (parts.length < 2) {
        errors.add('سطر $lineNo: يُتوقَّع رقم كرت ورمز سري');
        continue;
      }

      final serial = parts[0];
      final secret = parts[1];
      if (serial.isEmpty || secret.isEmpty) {
        errors.add('سطر $lineNo: حقول فارغة');
        continue;
      }
      if (seen.contains(serial)) {
        errors.add('سطر $lineNo: تكرار رقم الكرت $serial');
        continue;
      }
      seen.add(serial);
      drafts.add(
        CardImportDraft(
          serialNumber: serial,
          secretCode: secret,
          format: CardImportFormat.serialAndPin,
        ),
      );
    }

    return CardImportParseResult(
      drafts: drafts,
      errors: errors,
      format: format,
    );
  }
}
