import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';

/// Independent blocked-phone list (not the customer blacklist status).
///
/// Numbers are stored canonicalized. A match on the SMS sender *or* any
/// phone-like token in the raw body rejects the event before parse/credit.
final class LocalBlockedNumberService {
  LocalBlockedNumberService({
    required this.settings,
    Clock? clock,
  }) : clock = clock ?? const SystemClock();

  final SettingsRepository settings;
  final Clock clock;

  Future<List<String>> list() async => _read();

  Future<bool> isBlocked(String raw) async {
    final canonical = PhoneNormalizer.canonicalize(raw) ?? raw.trim();
    if (canonical.isEmpty) return false;
    final stored = await _read();
    if (stored.contains(canonical)) return true;
    for (final item in stored) {
      if (PhoneNormalizer.samePhone(item, raw)) return true;
    }
    return false;
  }

  /// True when [sourceKey] or any phone-like token in [body] is blocked.
  Future<bool> hitsRawEvent({
    required String sourceKey,
    required String body,
  }) async {
    if (await isBlocked(sourceKey)) return true;
    for (final token in _phoneTokens(body)) {
      if (await isBlocked(token)) return true;
    }
    return false;
  }

  Future<Result<void>> add(String raw) async {
    final canonical = PhoneNormalizer.canonicalize(raw) ?? raw.trim();
    if (canonical.isEmpty || canonical.length < 7) {
      return const Failure(
        AppFailure(code: 'invalid_phone', message: 'رقم غير صالح'),
      );
    }
    final current = await _read();
    if (current.contains(canonical)) return const Success(null);
    return _write([...current, canonical]..sort());
  }

  Future<Result<void>> remove(String raw) async {
    final canonical = PhoneNormalizer.canonicalize(raw) ?? raw.trim();
    final current = await _read();
    final next = current
        .where((n) => n != canonical && !PhoneNormalizer.samePhone(n, raw))
        .toList();
    return _write(next);
  }

  Future<List<String>> _read() async {
    final found = await settings.find(SettingKeys.blockedPhones);
    if (found is! Success<AppSetting?>) return const [];
    final raw = found.value?.value.trim();
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } on Object {
      return const [];
    }
  }

  Future<Result<void>> _write(List<String> phones) {
    return settings.save(
      AppSetting(
        key: SettingKeys.blockedPhones,
        value: jsonEncode(phones),
        updatedAt: clock.now(),
      ),
    );
  }

  static Iterable<String> _phoneTokens(String body) {
    final matches = RegExp(r'[+\d][\d\s-]{6,16}\d').allMatches(body);
    return matches.map((m) => m.group(0)!);
  }
}
