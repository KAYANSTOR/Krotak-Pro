import 'dart:convert';
import 'dart:typed_data';

/// Supported commercial card-import file kinds (plan §9).
enum CardImportFileKind {
  csv,
  pdf,
  xlsx,
  unsupported,
}

/// Result of validating and reading a card-import file into text rows.
final class CardImportFileReadResult {
  const CardImportFileReadResult({
    required this.kind,
    required this.text,
    this.errorCode,
    this.errorMessage,
  });

  final CardImportFileKind kind;
  final String text;
  final String? errorCode;
  final String? errorMessage;

  bool get isOk =>
      errorCode == null &&
      kind != CardImportFileKind.unsupported &&
      text.trim().isNotEmpty;

  static CardImportFileReadResult unsupported({
    required String code,
    required String message,
  }) {
    return CardImportFileReadResult(
      kind: CardImportFileKind.unsupported,
      text: '',
      errorCode: code,
      errorMessage: message,
    );
  }
}

/// Reads **PDF / Excel (.xlsx) / CSV** only into a text body for
/// [CardImportParser].
///
/// Validation is not extension-only: magic bytes / signatures are checked so
/// a renamed image or binary cannot pass as CSV/PDF/XLSX.
abstract final class CardImportFileReader {
  /// Allowed filename extensions for the system file picker.
  static const allowedExtensions = <String>['pdf', 'xlsx', 'csv'];

  static CardImportFileReadResult read({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) {
      return CardImportFileReadResult.unsupported(
        code: 'empty_file',
        message: 'الملف فارغ',
      );
    }

    final lower = fileName.trim().toLowerCase();
    final kind = _detectKind(fileName: lower, bytes: bytes);

    switch (kind) {
      case CardImportFileKind.pdf:
        final text = _extractPdfTjLiterals(bytes);
        if (text.trim().isEmpty) {
          return CardImportFileReadResult.unsupported(
            code: 'pdf_no_extractable_text',
            message:
                'تعذر استخراج نص من PDF (قد يكون مصوّراً ويحتاج OCR غير متوفر)',
          );
        }
        return CardImportFileReadResult(kind: kind, text: text);
      case CardImportFileKind.csv:
        return CardImportFileReadResult(
          kind: kind,
          text: _decodeUtf8StripBom(bytes),
        );
      case CardImportFileKind.xlsx:
        final text = _extractXlsxSharedStringsAndSheet(bytes);
        if (text.trim().isEmpty) {
          return CardImportFileReadResult.unsupported(
            code: 'xlsx_parse_failed',
            message: 'تعذر قراءة ورقة Excel',
          );
        }
        return CardImportFileReadResult(kind: kind, text: text);
      case CardImportFileKind.unsupported:
        return CardImportFileReadResult.unsupported(
          code: 'unsupported_file_type',
          message:
              'يُسمح فقط بملفات PDF أو Excel (.xlsx) أو CSV. تم رفض الملف.',
        );
    }
  }

  static CardImportFileKind _detectKind({
    required String fileName,
    required Uint8List bytes,
  }) {
    final isPdfMagic = bytes.length >= 5 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2d; // -
    final isZipMagic = bytes.length >= 4 &&
        bytes[0] == 0x50 && // P
        bytes[1] == 0x4b && // K
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);

    if (fileName.endsWith('.pdf')) {
      if (!isPdfMagic) {
        return CardImportFileKind.unsupported;
      }
      return CardImportFileKind.pdf;
    }
    if (fileName.endsWith('.xlsx')) {
      if (!isZipMagic) {
        return CardImportFileKind.unsupported;
      }
      return CardImportFileKind.xlsx;
    }
    if (fileName.endsWith('.csv')) {
      // Reject obvious binary / image / PDF masquerading as CSV.
      if (isPdfMagic || isZipMagic) return CardImportFileKind.unsupported;
      if (_looksLikeImage(bytes)) return CardImportFileKind.unsupported;
      return CardImportFileKind.csv;
    }
    return CardImportFileKind.unsupported;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return true;
    }
    // JPEG
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return true;
    }
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    // WEBP (RIFF....WEBP)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
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

  static String _extractPdfTjLiterals(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final out = <String>[];
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

  /// Minimal XLSX extract: sharedStrings + first sheet cell values as lines.
  /// Does not require an external spreadsheet package — reads ZIP entries
  /// as UTF-8 XML and pulls `<t>` / `<v>` text nodes.
  static String _extractXlsxSharedStringsAndSheet(Uint8List bytes) {
    try {
      final asLatin = latin1.decode(bytes, allowInvalid: true);
      // Prefer shared strings table text nodes.
      final shared = <String>[];
      final tRe = RegExp(r'<t[^>]*>([^<]*)</t>', caseSensitive: false);
      for (final m in tRe.allMatches(asLatin)) {
        final v = m.group(1)?.trim() ?? '';
        if (v.isNotEmpty) shared.add(_xmlUnescape(v));
      }
      if (shared.isNotEmpty) {
        return shared.join('\n');
      }
      // Fallback: numeric/inline values.
      final vRe = RegExp(r'<v>([^<]+)</v>', caseSensitive: false);
      final values = <String>[];
      for (final m in vRe.allMatches(asLatin)) {
        final v = m.group(1)?.trim() ?? '';
        if (v.isNotEmpty) values.add(v);
      }
      return values.join('\n');
    } catch (_) {
      return '';
    }
  }

  static String _xmlUnescape(String s) {
    return s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
