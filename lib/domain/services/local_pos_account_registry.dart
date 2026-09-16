import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/customer.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import 'services.dart';

/// Persists POS↔ledger bindings in [SettingKeys.posAccounts] as JSON.
/// The customer ledger remains the single financial book for POS balances.
final class LocalPosAccountRegistry {
  LocalPosAccountRegistry({
    required this.settings,
    required this.clock,
    this.customers,
    this.customerService,
    this.pointsOfSale,
    this.ids,
  });

  final SettingsRepository settings;
  final Clock clock;
  final CustomerRepository? customers;
  final CustomerService? customerService;
  final PointOfSaleRepository? pointsOfSale;
  final IdGenerator? ids;

  Future<Result<List<PosAccount>>> listAll() async {
    final found = await settings.find(SettingKeys.posAccounts);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final raw = (found as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) return const Success(<PosAccount>[]);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const Success(<PosAccount>[]);
      return Success(decoded.whereType<Map>().map((row) => PosAccount.fromJson(Map<String, Object?>.from(row))).toList(growable: false));
    } catch (error) {
      return Failure(AppFailure(code: 'pos_accounts_corrupt', message: error.toString()));
    }
  }

  Future<Result<PosAccount?>> findByPosId(String posId) async {
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    final rows = (all as Success<List<PosAccount>>).value;
    for (final account in rows) {
      if (account.posId == posId && account.customerId.trim().isNotEmpty) return Success(account);
    }
    for (final account in rows) {
      if (account.posId == posId && account.customerId.trim().isEmpty) {
        return _ensureBinding(
          posId: account.posId,
          name: account.name,
          identifiers: account.identifiers,
          notifyPhone: account.notifyPhone,
          status: account.status,
          percentageMode: account.percentageMode,
        );
      }
    }

    final posRepo = pointsOfSale;
    if (posRepo == null) return const Success(null);
    final foundPos = await posRepo.findById(posId);
    if (foundPos is Failure<PointOfSale?>) return Failure(foundPos.error);
    final pos = (foundPos as Success<PointOfSale?>).value;
    if (pos == null) return const Success(null);
    return _ensureBinding(
      posId: pos.id,
      name: pos.name,
      identifiers: <String>[pos.name],
      status: pos.status,
    );
  }

  Future<Result<PosAccount?>> findByIdentifier(String raw) async {
    final needle = _normalize(raw);
    if (needle.isEmpty) return const Success(null);
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    PosAccount? hit;
    for (final account in (all as Success<List<PosAccount>>).value) {
      if (account.status != PointOfSaleStatus.active || account.customerId.trim().isEmpty) continue;
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
    if (account.posId.trim().isEmpty) {
      return const Failure(AppFailure(code: 'pos_id_required', message: 'Point of sale id is required'));
    }
    final customerId = account.customerId.trim();
    if (customerId.isEmpty) return _saveWithAutomaticLedgerBinding(account);
    return _saveBound(account.copyWith(customerId: customerId));
  }

  Future<Result<void>> _saveWithAutomaticLedgerBinding(PosAccount account) async {
    final ensured = await _ensureBinding(
      posId: account.posId,
      name: account.name,
      identifiers: account.identifiers,
      notifyPhone: account.notifyPhone,
      status: account.status,
      percentageMode: account.percentageMode,
    );
    if (ensured is Failure<PosAccount?>) return Failure(ensured.error);
    final resolved = (ensured as Success<PosAccount?>).value;
    if (resolved == null || resolved.customerId.trim().isEmpty) {
      return const Failure(AppFailure(code: 'pos_customer_binding_required', message: 'Point of sale must be linked to a customer ledger account'));
    }
    return _saveBound(account.copyWith(customerId: resolved.customerId));
  }

  Future<Result<PosAccount?>> _ensureBinding({
    required String posId,
    required String name,
    required List<String> identifiers,
    String? notifyPhone,
    PointOfSaleStatus status = PointOfSaleStatus.active,
    PosPercentageMode percentageMode = PosPercentageMode.defaultCategory,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return const Failure(AppFailure(code: 'pos_name_required', message: 'Point of sale name is required'));
    final customerRepo = customers;
    final creator = customerService;
    final idGenerator = ids;
    if (customerRepo == null || creator == null || idGenerator == null) {
      return const Failure(AppFailure(code: 'pos_customer_binding_required', message: 'Point of sale must be linked to a customer ledger account'));
    }

    final stableIdentifier = 'pos:$posId';
    final found = await customerRepo.findByIdentifier(stableIdentifier);
    if (found is Failure<Customer?>) return Failure(found.error);
    Customer? customer = (found as Success<Customer?>).value;
    if (customer == null) {
      final created = await creator.create(
        displayName: trimmedName,
        identifierType: CustomerIdentifierType.externalReference,
        identifierValue: stableIdentifier,
      );
      if (created is Failure<Customer>) return Failure(created.error);
      customer = (created as Success<Customer>).value;
    }

    final normalizedIdentifiers = <String>{trimmedName, ...identifiers.map((e) => e.trim()).where((e) => e.isNotEmpty)}.toList(growable: false);
    final bound = PosAccount(
      posId: posId,
      customerId: customer.id,
      name: trimmedName,
      identifiers: normalizedIdentifiers,
      notifyPhone: notifyPhone,
      status: status,
      percentageMode: percentageMode,
    );
    final saved = await _saveBound(bound);
    if (saved is Failure<void>) return Failure(saved.error);
    return Success(bound);
  }

  Future<Result<void>> _saveBound(PosAccount account) async {
    final all = await listAll();
    if (all is Failure<List<PosAccount>>) return Failure(all.error);
    final next = [
      for (final existing in (all as Success<List<PosAccount>>).value)
        if (existing.posId != account.posId) existing,
      account,
    ];
    return settings.save(AppSetting(key: SettingKeys.posAccounts, value: jsonEncode(next.map((e) => e.toJson()).toList()), updatedAt: clock.now()));
  }

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (PhoneNormalizer.isPhoneLike(trimmed)) return PhoneNormalizer.forStorage(trimmed, asPhone: true);
    return trimmed.toLowerCase();
  }
}
