import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../entities/setting.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';

/// Persists POS\u2194ledger bindings in [SettingKeys.posAccounts] as JSON.
/// No extra Drift table: the customer ledger remains the single financial book.
final class LocalPosAccountRegistry {
  const LocalPosAccountRegistry({required this.settings, required this.clock});

  final SettingsRepository settings;
  final Clock clock;

  Future<Result<List<PosAccount>>> listAll() async {
    final found = await settings.find(SettingKeys.posAccounts);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final raw = (found as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) return const Success(<PosAccount>[]);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const Success(<PosAccount>[]);
      return Success(
        decoded
            .whereType<Map>()
            .map((row) => PosAccount.fromJson(Map<String, Object?>.from(row)))
            .toList(growable: false),
      );
    } catch (error) {
      return Failure(AppFailure(code: 'pos_accounts_corrupt', message: error.toString()));
    }
  }

  Future<Result<PosAccount?>> findByPosId(String posId) async {
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    for (final account in (all as Success<List<PosAccount>>).value) {
      if (account.posId == posId) return Success(account);
    }
    return const Success(null);
  }

  /// Resolves an active POS from payment-facing identifiers contained in
  /// the raw inbound sender/body. This is only a routing signal; template
  /// matching still decides whether the message is accepted.
  Future<Result<PosAccount?>> findByMessage({
    required String sender,
    required String body,
  }) async {
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    final active = (all as Success<List<PosAccount>>).value
        .where((account) => account.status == PointOfSaleStatus.active)
        .toList(growable: false);

    PosAccount? hit;
    for (final account in active) {
      final configuredIdentifiers = <String>[
        ...account.identifiers,
        if (account.notifyPhone != null) account.notifyPhone!,
      ];
      final matched = configuredIdentifiers.any(
        (identifier) => _messageContainsIdentifier(
          sender: sender,
          body: body,
          identifier: identifier,
        ),
      );
      if (!matched) continue;

      if (hit != null && hit.posId != account.posId) {
        return const Failure(
          AppFailure(
            code: 'pos_identifier_ambiguous',
            message: 'Inbound message matches more than one active POS account',
          ),
        );
      }
      hit = account;
    }
    return Success(hit);
  }

  Future<Result<PosAccount?>> findByIdentifier(String raw) async {
    final needle = _normalize(raw);
    if (needle.isEmpty) return const Success(null);
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    PosAccount? hit;
    for (final account in (all as Success<List<PosAccount>>).value) {
      if (account.status != PointOfSaleStatus.active) continue;
      final keys = <String>{_normalize(account.name), ...account.identifiers.map(_normalize)};
      if (keys.contains(needle)) {
        if (hit != null && hit.posId != account.posId) {
          return const Failure(AppFailure(code: 'pos_identifier_ambiguous', message: 'Identifier matches more than one point of sale'));
        }
        hit = account;
      }
    }
    return Success(hit);
  }

  Future<Result<void>> save(PosAccount account) async {
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    final next = [
      for (final existing in (all as Success<List<PosAccount>>).value)
        if (existing.posId != account.posId) existing,
      account,
    ];
    return settings.save(AppSetting(key: SettingKeys.posAccounts, value: jsonEncode(next.map((e) => e.toJson()).toList()), updatedAt: clock.now()));
  }

  static bool _messageContainsIdentifier({
    required String sender,
    required String body,
    required String identifier,
  }) {
    final needle = identifier.trim();
    if (needle.isEmpty) return false;

    final combined = '$sender\n$body';
    if (PhoneNormalizer.isPhoneLike(needle)) {
      final target = PhoneNormalizer.canonicalize(needle);
      if (target == null) return false;
      if (PhoneNormalizer.samePhone(sender, needle)) return true;

      final numericTokens = RegExp(r'\+?\d[\d\s().-]{5,}\d')
          .allMatches(combined)
          .map((m) => m.group(0)!)
          .toList(growable: false);
      return numericTokens.any((token) =>
          PhoneNormalizer.canonicalize(token) == target);
    }

    final normalizedNeedle = _normalize(needle);
    if (normalizedNeedle.length < 3) return false;
    return combined.toLowerCase().contains(normalizedNeedle);
  }

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (PhoneNormalizer.isPhoneLike(trimmed)) return PhoneNormalizer.forStorage(trimmed, asPhone: true);
    return trimmed.toLowerCase();
  }
}
