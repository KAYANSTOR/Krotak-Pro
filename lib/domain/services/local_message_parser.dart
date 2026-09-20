import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import 'services.dart';

/// Matches incoming SMS bodies against active [TransferTemplate] patterns.
///
/// Placeholders (both styles supported, same engine — no second parser):
/// - `{amount}` / `%amount` → digits with optional decimal/comma; Arabic-Indic digits OK
/// - `{phone}` / `%phone` → sendable phone token
/// - `{account}` / `%account` → account/name (spaces allowed, non-greedy)
/// - `{ref}` / `%ref` → operation reference (allows decimals like 68488.36)
/// - `{qty}` / `%qty` → POS quantity, 1..20
/// - `{dest}` / `%dest` → POS delivery destination override
///
/// Active templates are tried in ascending [TransferTemplate.priority] order.
/// Call [replaceTemplates] after saving templates so SMS path picks them up
/// without restarting the app.
final class LocalMessageParser implements MessageParser {
  LocalMessageParser({
    required List<TransferTemplate> templates,
    this.defaultCurrencyCode = 'YER',
  }) : _templates = _sorted(templates);

  List<TransferTemplate> _templates;
  final String defaultCurrencyCode;

  List<TransferTemplate> get templates => List.unmodifiable(_templates);

  /// Hot-reload templates from the repository without recreating the parser graph.
  void replaceTemplates(List<TransferTemplate> templates) {
    _templates = _sorted(templates);
  }

  static List<TransferTemplate> _sorted(List<TransferTemplate> templates) {
    final list = List<TransferTemplate>.of(templates);
    list.sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(list);
  }

  static final Set<String> _regexMeta = <String>{
    '.',
    '+',
    '*',
    '?',
    '^',
    r'$',
    '(',
    ')',
    '|',
    '[',
    ']',
    '{',
    '}',
    r'\',
  };

  @override
  Result<ParsedTransfer> parse(IncomingMessage message) {
    final active = _templates.where((t) => t.isActive).toList(growable: false);
    if (active.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'no_active_template',
          message: 'No active transfer template configured',
        ),
      );
    }

    final body = _normalizeBody(message.body);
    for (final template in active) {
      final balanceRequest = _tryBalanceRequest(template, message.id, message.sender, body);
      if (balanceRequest != null) return Success(balanceRequest);
      final instant = _tryInstantCharge(template, message.id, message.sender, body);
      if (instant != null) return Success(instant);
      final parsed = _tryMatch(template, message.id, message.sender, body);
      if (parsed != null) return Success(parsed);
    }

    return const Failure(
      AppFailure(
        code: 'message_not_matched',
        message: 'Message body did not match any active transfer template',
      ),
    );
  }

  ParsedTransfer? _tryMatch(
    TransferTemplate template,
    String messageId,
    String sender,
    String body,
  ) {
    final isPos = template.posId != null || !template.requireReference;
    final regex = _patternToRegex(template.pattern, allowImplicitPosQuantity: isPos);
    final match = regex.firstMatch(body);
    if (match == null) return null;

    final amountRaw = match.namedGroup('amount');
    if (amountRaw == null || amountRaw.isEmpty) return null;

    final minor = _parseAmountToMinor(amountRaw);
    if (minor == null || minor <= 0) return null;

    final phone = _group(match, 'phone');
    final account = _group(match, 'account');
    final ref = _group(match, 'ref');
    final destinationRaw = _group(match, 'dest');
    final qtyRaw = _group(match, 'qty');
    // `ref` (transaction reference) is required by default — this is a
    // deliberate financial safety net: a template with no captured
    // reference can't be de-duplicated against a real bank transaction.
    // Only templates that explicitly opt out (`requireReference: false`,
    // e.g. POS card-request templates that carry no reference at all)
    // skip this check.
    if (template.requireReference && (ref == null || ref.isEmpty)) return null;

    String? identifier;
    TransferIdentifierType type;
    if (phone != null && phone.isNotEmpty) {
      final normalizedPhone = _normalizePhone(phone);
      if (normalizedPhone == null) return null;
      identifier = normalizedPhone;
      type = TransferIdentifierType.phone;
    } else if (account != null && account.isNotEmpty) {
      identifier = account.trim();
      type = TransferIdentifierType.account;
    } else {
      return null;
    }

    var quantity = 1;
    if (qtyRaw != null && qtyRaw.isNotEmpty) {
      quantity = int.tryParse(qtyRaw) ?? 0;
    } else if (isPos) {
      final trailing = RegExp(r'\s+(\d{1,2})
  }

  ParsedTransfer? _tryInstantCharge(TransferTemplate template, String messageId, String sender, String body) {
    if (template.posId == null || template.posId!.trim().isEmpty) return null;
    final ledgerPhone = _normalizePhone(sender);
    if (ledgerPhone == null) return null;
    String? destination;
    String? amountRaw;
    final charge = RegExp(r'^شحن\s+(\+?[\d]{7,15})\s+([\d]+(?:[.,]\d{1,2})?)
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern, {bool allowImplicitPosQuantity = false}) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}')
        .replaceAll('%qty', '{qty}')
        .replaceAll('%dest', '{dest}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      if (unified.startsWith('{qty}', i)) {
        buf.write(r'(?<qty>\d{1,2})');
        i += '{qty}'.length;
        continue;
      }
      if (unified.startsWith('{dest}', i)) {
        buf.write(r'(?<dest>\+?[\d]{7,15})');
        i += '{dest}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    if (allowImplicitPosQuantity && !unified.contains('{qty}')) {
      buf.write(r'(?:\s+(?<qty>\d{1,2}))?');
    }
    return RegExp('^' + buf.toString() + r'
  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      posId: template.posId,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
    if (charge != null) {
      destination = charge.group(1);
      amountRaw = charge.group(2);
    } else {
      final send = RegExp(r'^ارسل\s+كرت\s+([\d]+(?:[.,]\d{1,2})?)\s+الى\s+(\+?[\d]{7,15})
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      if (unified.startsWith('{qty}', i)) {
        buf.write(r'(?<qty>\d{1,2})');
        i += '{qty}'.length;
        continue;
      }
      if (unified.startsWith('{dest}', i)) {
        buf.write(r'(?<dest>\+?[\d]{7,15})');
        i += '{dest}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp('^${buf.toString()}
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (send != null) {
        amountRaw = send.group(1);
        destination = send.group(2);
      }
    }
    if (destination == null || amountRaw == null) return null;
    final minor = _parseAmountToMinor(amountRaw);
    final delivery = _normalizePhone(destination);
    if (minor == null || minor <= 0 || delivery == null) return null;
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: ledgerPhone,
      identifierType: TransferIdentifierType.phone,
      reference: '',
      templateId: template.id,
      rawIdentifier: sender,
      deliveryOverride: delivery,
      instantCharge: true,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      if (unified.startsWith('{qty}', i)) {
        buf.write(r'(?<qty>\d{1,2})');
        i += '{qty}'.length;
        continue;
      }
      if (unified.startsWith('{dest}', i)) {
        buf.write(r'(?<dest>\+?[\d]{7,15})');
        i += '{dest}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp('^${buf.toString()}
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
    if (charge != null) {
      destination = charge.group(1);
      amountRaw = charge.group(2);
    } else {
      final send = RegExp(r'^ارسل\s+كرت\s+([\d]+(?:[.,]\d{1,2})?)\s+الى\s+(\+?[\d]{7,15})
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      if (unified.startsWith('{qty}', i)) {
        buf.write(r'(?<qty>\d{1,2})');
        i += '{qty}'.length;
        continue;
      }
      if (unified.startsWith('{dest}', i)) {
        buf.write(r'(?<dest>\+?[\d]{7,15})');
        i += '{dest}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp('^${buf.toString()}
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (send != null) {
        amountRaw = send.group(1);
        destination = send.group(2);
      }
    }
    if (destination == null || amountRaw == null) return null;
    final minor = _parseAmountToMinor(amountRaw);
    final delivery = _normalizePhone(destination);
    if (minor == null || minor <= 0 || delivery == null) return null;
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: ledgerPhone,
      identifierType: TransferIdentifierType.phone,
      reference: '',
      templateId: template.id,
      rawIdentifier: sender,
      deliveryOverride: delivery,
      instantCharge: true,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      if (unified.startsWith('{qty}', i)) {
        buf.write(r'(?<qty>\d{1,2})');
        i += '{qty}'.length;
        continue;
      }
      if (unified.startsWith('{dest}', i)) {
        buf.write(r'(?<dest>\+?[\d]{7,15})');
        i += '{dest}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp('^${buf.toString()}
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
, caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
).firstMatch(body);
      if (trailing != null) quantity = int.tryParse(trailing.group(1)!) ?? 0;
    }
    if (quantity < 1 || quantity > 20) return null;
    String? deliveryOverride;
    if (destinationRaw != null && destinationRaw.isNotEmpty) {
      deliveryOverride = _normalizePhone(destinationRaw);
      if (deliveryOverride == null) return null;
    }
    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: identifier,
      identifierType: type,
      reference: ref ?? '',
      templateId: template.id,
      rawIdentifier: phone ?? account,
      quantity: quantity,
      deliveryOverride: deliveryOverride,
      instantCharge: false,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  String? _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.startsWith('+')) {
      final rest = s.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 7 || rest.length > 15) return null;
      return '+$rest';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  RegExp _patternToRegex(String pattern) {
    final unified = _normalizeBody(pattern)
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
      // فواصل وعلامات قد تختلف فيها المسافات بين المصدر والرسالة الفعلية
      // (`رص:{ref}` مقابل `رص: {ref}`) — نتجاهل المسافات حولها في الاتجاهين.
      if (_flexibleSeparators.contains(unified[i])) {
        buf.write(r'\s*');
        buf.write('\\');
        buf.write(unified[i]);
        buf.write(r'\s*');
        i++;
        continue;
      }
      if (unified.startsWith('{amount}', i)) {
        buf.write(r'(?<amount>[\d]+(?:[.,]\d{1,2})?)');
        i += '{amount}'.length;
        continue;
      }
      if (unified.startsWith('{phone}', i)) {
        buf.write(r'(?<phone>\+?[\d]{7,15})');
        i += '{phone}'.length;
        continue;
      }
      if (unified.startsWith('{account}', i)) {
        // Allow Arabic names with spaces (e.g. شيماء عثمان) — non-greedy.
        buf.write(r'(?<account>.+?)');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        // Allow decimal refs like 68488.36 (common in Yemen wallet SMS).
        buf.write(r'(?<ref>\S{1,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        // `\s*` لا `\s+`: النموذج والرسالة قد يختلفان في وجود فراغ واحد فقط.
        buf.write(r'\s*');
        while (i + 1 < unified.length &&
            (unified[i + 1] == ' ' ||
                unified[i + 1] == '\t' ||
                unified[i + 1] == '\n')) {
          i++;
        }
      } else if (_regexMeta.contains(ch)) {
        buf.write('\\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
      i++;
    }

    return RegExp(buf.toString(), caseSensitive: false, unicode: true);
  }

  /// Collapse whitespace, strip bidi marks, unify Arabic letter variants, and
  /// map Eastern digits — must be applied identically to the pattern and the
  /// incoming body so harmless spelling differences never block a match.
  String _normalizeBody(String input) {
    var s = _normalizeDigits(input.trim());
    s = s
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\u00a0'), ' ')
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u06d6-\u06ed]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return s.trim();
  }

  /// علامات ترقيم/فواصل تُطابَق مع تجاهل المسافات حولها.
  static const _flexibleSeparators = <String>{':', '-', '/', ',', '.', '\u060c'};

  String _normalizeDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      final p = persian.indexOf(ch);
      if (p >= 0) {
        out.write(p);
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
