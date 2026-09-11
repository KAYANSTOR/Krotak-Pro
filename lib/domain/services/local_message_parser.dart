import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import 'services.dart';

/// Parses incoming SMS bodies against active [TransferTemplate] patterns.
///
/// Pattern placeholders:
/// - `{amount}`  → digits with optional decimal
/// - `{phone}`   → customer identifier
/// - `{ref}`     → reference token
final class LocalMessageParser implements MessageParser {
  const LocalMessageParser({
    required this.templates,
    this.defaultCurrencyCode = 'YER',
  });

  final List<TransferTemplate> templates;
  final String defaultCurrencyCode;

  @override
  Result<ParsedTransfer> parse(IncomingMessage message) {
    final active = templates.where((t) => t.isActive).toList();
    if (active.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'no_active_template',
          message: 'No active transfer template configured',
        ),
      );
    }

    for (final template in active) {
      final parsed = _tryMatch(template, message);
      if (parsed != null) return Success(parsed);
    }

    return const Failure(
      AppFailure(
        code: 'message_not_matched',
        message: 'Message body did not match any active transfer template',
      ),
    );
  }

  ParsedTransfer? _tryMatch(TransferTemplate template, IncomingMessage message) {
    final regex = _patternToRegex(template.pattern);
    final match = regex.firstMatch(message.body.trim());
    if (match == null) return null;

    final amountRaw = match.namedGroup('amount');
    final phone = match.namedGroup('phone');
    final ref = match.namedGroup('ref');

    if (amountRaw == null || phone == null || ref == null) return null;
    if (phone.isEmpty || ref.isEmpty) return null;

    final minor = _parseAmountToMinor(amountRaw);
    if (minor == null || minor <= 0) return null;

    return ParsedTransfer(
      messageId: message.id,
      amount: Money(minorUnits: minor, currencyCode: defaultCurrencyCode),
      customerIdentifier: phone.trim(),
      reference: ref.trim(),
    );
  }

  RegExp _patternToRegex(String pattern) {
    final escaped = pattern
        .replaceAllMapped(
          RegExp(r'[.*+?^${}()|[\]\\]'),
          (m) {
            final ch = m.group(0)!;
            if (ch == '{' || ch == '}') return ch;
            return '\\$ch';
          },
        )
        .replaceAll('{amount}', r'(?<amount>[\d]+(?:[.,]\d{1,2})?)')
        .replaceAll('{phone}', r'(?<phone>\+?\d{7,15})')
        .replaceAll('{ref}', r'(?<ref>[\w\-]{3,64})');

    return RegExp(escaped, caseSensitive: false, unicode: true);
  }

  int? _parseAmountToMinor(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }
}
