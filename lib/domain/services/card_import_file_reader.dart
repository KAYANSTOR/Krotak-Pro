import 'dart:convert';
import 'dart:typed_data';

/// Kind of card-import file recognized by [CardImportFileReader].
enum CardImportFileKind {
  csv,
  pdf,
  text,
  unknown,
}

/// Result of reading raw file bytes into importable text.
final class CardImportFileReadResult {
  const CardImportFileReadResult({
    required this.kind,
    required this.text,
  });

  final CardImportFileKind kind;
  final String text;
}

/// Reads CSV / plain-text / simple PDF card stock files into a single text
/// body for [CardImportParser].
///
/// - CSV/TXT: UTF-8 with optional BOM stripped.
/// - PDF: extracts `(literal) Tj` string operands (minimal PDF text pull).
abstract final class CardImportFileReader {
  static CardImportFileReadResult read({
    required String fileName,
    required Uint8List bytes,
  }) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) {
      return CardImportFileReadResult(
        kind: CardImportFileKind.pdf,
        text: _extractPdfTjLiterals(bytes),
      );
    }
    if (lower.endsWith('.csv')) {
      return CardImportFileReadResult(
        kind: CardImportFileKind.csv,
        text: _decodeUtf8StripBom(bytes),
      );
    }
    if (lower.endsWith('.txt') || lower.endsWith('.text')) {
      return CardImportFileReadResult(
        kind: CardImportFileKind.text,
        text: _decodeUtf8StripBom(bytes),
      );
    }
    // Default: treat as UTF-8 text so paste/unknown extensions still work.
    return CardImportFileReadResult(
      kind: CardImportFileKind.unknown,
      text: _decodeUtf8StripBom(bytes),
    );
  }

  static String _decodeUtf8StripBom(Uint8List bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      start = 3;
    }
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  /// Pulls PDF string operands that appear before a `Tj` operator.
  /// Handles simple `(literal) Tj` forms used in stock export PDFs.
  static String _extractPdfTjLiterals(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final out = <String>[];
    // Match sequences like: (10001) Tj
    final re = RegExp(r'\(([^)\\]*(?:\\.[^)\\]*)*)\)\s*Tj');
    for (final m in re.allMatches(raw)) {
      final lit = m.group(1);
      if (lit == null || lit.isEmpty) continue;
      out.add(_unescapePdfString(lit));
    }
    return out.join('\n');
  }

  static String _unescapePdfString(String input) {
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == r'\' && i + 1 < input.length) {
        final next = input[i + 1];
        switch (next) {
          case 'n':
            buf.write('\n');
            break;
          case 'r':
            buf.write('\r');
            break;
          case 't':
            buf.write('\t');
            break;
          case 'b':
            buf.write('\b');
            break;
          case 'f':
            buf.write('\f');
            break;
          case '(':
          case ')':
          case r'\':
            buf.write(next);
            break;
          default:
            buf.write(next);
        }
        i++;
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }
}
