import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import 'services.dart';

/// Matches incoming SMS bodies against active [TransferTemplate] patterns.
///
/// Placeholders (both styles supported, same engine — no second parser):
/// - `{amount}` / `%amount` → digits with optional decimal/comma; Arabic-Indic digits OK
/// - `{phone}` / `%phone` → sendable phone token
/// - `{account}` / `%account` → non-phone account/name/code
/// - `{ref}` / `%ref` → operation reference for idempotency
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
    return List<TransferTemplate>.unmodifiable(list);
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

    final body = _normalizeDigits(message.body.trim());
    for (final template in active) {
      final parsed = _tryMatch(template, message.id, body);
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
    String body,
  ) {
    final regex = _patternToRegex(template.pattern);
    final match = regex.firstMatch(body);
    if (match == null) return null;

    final amountRaw = match.namedGroup('amount');
    if (amountRaw == null || amountRaw.isEmpty) return null;

    final minor = _parseAmountToMinor(amountRaw);
    if (minor == null || minor <= 0) return null;

    final phone = _group(match, 'phone');
    final account = _group(match, 'account');
    final ref = _group(match, 'ref');

    final resolved = _resolveIdentifier(
      phone: phone,
      account: account,
      ref: ref,
    );
    if (resolved == null || ref == null || ref.isEmpty) return null;

    return ParsedTransfer(
      messageId: messageId,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: resolved.value,
      identifierType: resolved.type,
      reference: ref,
      templateId: template.id,
      rawIdentifier: resolved.raw,
    );
  }

  String? _group(RegExpMatch match, String name) {
    try {
      final v = match.namedGroup(name);
      if (v == null) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  ({String value, TransferIdentifierType type, String raw})? _resolveIdentifier({
    required String? phone,
    required String? account,
    required String? ref,
  }) {
    if (phone != null && phone.isNotEmpty) {
      final normalized = _normalizePhone(phone);
      if (normalized == null) return null;
      return (value: normalized, type: TransferIdentifierType.phone, raw: phone);
    }
    if (account != null && account.isNotEmpty) {
      final type = _classifyAccountToken(account);
      return (value: account, type: type, raw: account);
    }
    return null;
  }

  TransferIdentifierType _classifyAccountToken(String token) {
    if (RegExp(r'^[\d]+$').hasMatch(token) && token.length >= 4) {
      return TransferIdentifierType.account;
    }
    if (RegExp(r'^[\w\-]+$').hasMatch(token) && !RegExp(r'^\d+$').hasMatch(token)) {
      if (RegExp(r'\d').hasMatch(token) && RegExp(r'[A-Za-z]').hasMatch(token)) {
        return TransferIdentifierType.reference;
      }
      return TransferIdentifierType.name;
    }
    return TransferIdentifierType.account;
  }

  String? _normalizePhone(String raw) {
    var s = raw.trim();
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
    final unified = pattern
        .replaceAll('%amount', '{amount}')
        .replaceAll('%phone', '{phone}')
        .replaceAll('%account', '{account}')
        .replaceAll('%ref', '{ref}');

    final buf = StringBuffer();
    var i = 0;
    while (i < unified.length) {
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
        buf.write(r'(?<account>[^\s]{2,64})');
        i += '{account}'.length;
        continue;
      }
      if (unified.startsWith('{ref}', i)) {
        buf.write(r'(?<ref>[\w\-]{3,64})');
        i += '{ref}'.length;
        continue;
      }
      final ch = unified[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        buf.write(r'\s+');
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
