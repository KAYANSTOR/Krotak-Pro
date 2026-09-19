import 'dart:convert';
import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/setting.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';

final class LocalCardCatalogService implements CardCatalogService {
  const LocalCardCatalogService({
    required this.categories,
    required this.cards,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CardCategoryRepository categories;
  final CardRepository cards;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  @override
  Future<Result<CardCategory>> saveCategory(CardCategory category) {
    final name = category.name.trim();
    if (name.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_category_name', message: 'Category name is required'),
        ),
      );
    }
    if (category.faceValue.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_face_value', message: 'Face value must be positive'),
        ),
      );
    }

    final normalized = CardCategory(
      id: category.id.isEmpty ? ids.next('category') : category.id,
      name: name,
      faceValue: category.faceValue,
      isActive: category.isActive,
    );

    return unitOfWork.run(() async {
      final saved = await categories.save(normalized);
      if (saved is Failure<void>) return Failure(saved.error);
      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'card_category',
          entityId: normalized.id,
          action: 'saved',
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(normalized);
    });
  }

  @override
  Future<Result<int>> importCards({
    required String categoryId,
    required List<CardImportDraft> drafts,
  }) {
    return unitOfWork.run(() async {
      final found = await categories.findById(categoryId);
      if (found is Failure<CardCategory?>) return Failure(found.error);
      final category = (found as Success<CardCategory?>).value;
      if (category == null) {
        return const Failure(
          AppFailure(code: 'category_not_found', message: 'Category was not found'),
        );
      }
      if (!category.isActive) {
        return const Failure(
          AppFailure(code: 'category_inactive', message: 'Category is not active'),
        );
      }

      var imported = 0;
      for (final draft in drafts) {
        final serial = draft.serialNumber.trim();
        final secret = draft.secretCode.trim();
        final serialOnly = draft.format == CardImportFormat.serialOnly;
        if (serial.isEmpty) {
          return const Failure(
            AppFailure(
              code: 'invalid_card_import',
              message: 'رقم الكرت مطلوب',
            ),
          );
        }
        if (!serialOnly && secret.isEmpty) {
          return const Failure(
            AppFailure(
              code: 'invalid_card_import',
              message: 'رمز الكرت (PIN) مطلوب في وضع الرقم والرمز',
            ),
          );
        }

        final existingSerial = await cards.findBySerialNumber(serial);
        if (existingSerial is Failure<Card?>) return Failure(existingSerial.error);
        if ((existingSerial as Success<Card?>).value != null) {
          return const Failure(
            AppFailure(code: 'duplicate_serial', message: 'رقم الكرت موجود مسبقاً'),
          );
        }

        final saved = await cards.save(
          Card(
            id: ids.next('card'),
            categoryId: categoryId,
            serialNumber: serial,
            secretCode: serialOnly ? '' : secret,
            status: CardStatus.available,
          ),
        );
        if (saved is Failure<void>) return Failure(saved.error);
        imported += 1;
      }

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'card_category',
          entityId: categoryId,
          action: 'cards_imported',
          payloadJson: '{\"count\":$imported}',
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(imported);
    });
  }
}

final class LocalWalletCatalogService implements WalletCatalogService {
  LocalWalletCatalogService({required this.wallets, required this.auditLogs, required this.settings, required this.clock, required this.ids});
  final WalletRepository wallets;
  final AuditLogRepository auditLogs;
  final SettingsRepository settings;
  final Clock clock;
  final IdGenerator ids;
  static const _defaults = [
    (name: 'جيب', senderId: 'JAIB', sourceMode: WalletSourceMode.notification, packageName: 'com.ahd.jaib'),
    (name: 'جوالي', senderId: 'JAWALI', sourceMode: WalletSourceMode.sms, packageName: 'com.wecash.jawali'),
    (name: 'ون كاش', senderId: 'ONE CASH', sourceMode: WalletSourceMode.sms, packageName: 'com.one.onecustomer'),
    (name: 'فلوسك', senderId: 'FLOOSAK', sourceMode: WalletSourceMode.sms, packageName: 'co.ysys.floosak'),
  ];
  @override
  Future<Result<List<Wallet>>> listEnriched() async {
    final list = await wallets.listAll();
    if (list is Failure) return Failure((list as Failure).error);
    final extras = await _readExtras();
    final enriched = (list as Success<List<Wallet>>).value.map((w) {
      final e = extras[w.id];
      if (e == null) return w;
      final modeRaw = (e['sourceMode'] as String?) ?? 'sms';
      return w.copyWith(
        senderId: e['senderId'] as String? ?? w.senderId,
        sourceMode: modeRaw == 'notification' ? WalletSourceMode.notification : WalletSourceMode.sms,
        packageName: e['packageName'] as String? ?? w.packageName,
      );
    }).toList(growable: false);
    return Success(enriched);
  }
  @override
  Future<Result<Wallet>> saveWallet({required String name, String? senderId, WalletSourceMode sourceMode = WalletSourceMode.sms, String? packageName}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Failure(AppFailure(code: 'invalid_wallet_name', message: 'اسم المحفظة مطلوب'));
    final wallet = Wallet(id: ids.next('wallet'), name: trimmed, status: WalletStatus.active, createdAt: clock.now(), senderId: senderId?.trim().isEmpty == true ? null : senderId?.trim(), sourceMode: sourceMode, packageName: packageName?.trim().isEmpty == true ? null : packageName?.trim());
    final saved = await wallets.save(wallet);
    if (saved is Failure<void>) return Failure(saved.error);
    await _writeExtras(wallet.id, wallet.senderId, wallet.sourceMode, wallet.packageName);
    await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'wallet', entityId: wallet.id, action: 'saved', occurredAt: clock.now()));
    return Success(wallet);
  }
  @override
  Future<Result<Wallet>> updateWallet({required String id, required String name, required WalletStatus status, String? senderId, WalletSourceMode? sourceMode, String? packageName}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Failure(AppFailure(code: 'invalid_wallet_name', message: 'اسم المحفظة مطلوب'));
    final found = await wallets.findById(id);
    if (found is Failure<Wallet?>) return Failure(found.error);
    final existing = (found as Success<Wallet?>).value;
    if (existing == null) return const Failure(AppFailure(code: 'wallet_not_found', message: 'المحفظة غير موجودة'));
    final extras = await _readExtras();
    final prev = extras[id];
    final resolvedSender = senderId ?? prev?['senderId'] as String? ?? existing.senderId;
    final resolvedMode = sourceMode ?? ((prev?['sourceMode'] as String?) == 'notification' ? WalletSourceMode.notification : existing.sourceMode);
    final resolvedPkg = packageName ?? prev?['packageName'] as String? ?? existing.packageName;
    final updated = Wallet(id: existing.id, name: trimmed, status: status, createdAt: existing.createdAt, senderId: resolvedSender, sourceMode: resolvedMode, packageName: resolvedPkg);
    final saved = await wallets.save(updated);
    if (saved is Failure<void>) return Failure(saved.error);
    await _writeExtras(updated.id, updated.senderId, updated.sourceMode, updated.packageName);
    await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'wallet', entityId: updated.id, action: 'status_changed', payloadJson: '{\"status\":\"' + updated.status.name + '\"}', occurredAt: clock.now()));
    return Success(updated);
  }
  @override
  Future<Result<void>> ensureDefaultWallets() async {
    final existing = await wallets.listAll();
    if (existing is Failure) return Failure((existing as Failure).error);
    final byName = {
      for (final w in (existing as Success<List<Wallet>>).value)
        w.name.trim().toLowerCase(): w,
    };
    final extras = await _readExtras();
    for (final spec in _defaults) {
      final key = spec.name.toLowerCase();
      if (byName.containsKey(key)) {
        // Never overwrite operator-edited sender/mode/package on subsequent boots.
        final id = byName[key]!.id;
        if (!extras.containsKey(id)) {
          await _writeExtras(id, spec.senderId, spec.sourceMode, spec.packageName);
        }
        continue;
      }
      final r = await saveWallet(
        name: spec.name,
        senderId: spec.senderId,
        sourceMode: spec.sourceMode,
        packageName: spec.packageName,
      );
      if (r is Failure) return Failure((r as Failure).error);
    }
    await settings.save(
      AppSetting(
        key: SettingKeys.defaultWalletsSeeded,
        value: 'true',
        updatedAt: clock.now(),
      ),
    );
    return const Success(null);
  }
  Future<Map<String, Map<String, dynamic>>> _readExtras() async {
    final found = await settings.find(SettingKeys.walletExtras);
    if (found is! Success<AppSetting?> || found.value == null) return {};
    try {
      final decoded = jsonDecode(found.value!.value);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    } catch (_) { return {}; }
  }
  Future<void> _writeExtras(String id, String? senderId, WalletSourceMode mode, String? packageName) async {
    final map = await _readExtras();
    map[id] = {if (senderId != null && senderId.isNotEmpty) 'senderId': senderId, 'sourceMode': mode == WalletSourceMode.notification ? 'notification' : 'sms', if (packageName != null && packageName.isNotEmpty) 'packageName': packageName};
    await settings.save(AppSetting(key: SettingKeys.walletExtras, value: jsonEncode(map), updatedAt: clock.now()));
  }
}

final class LocalPointOfSaleCatalogService implements PointOfSaleCatalogService {
  const LocalPointOfSaleCatalogService({
    required this.pointsOfSale,
    required this.auditLogs,
    required this.clock,
    required this.ids,
  });

  final PointOfSaleRepository pointsOfSale;
  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;

  @override
  Future<Result<PointOfSale>> savePointOfSale({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Failure(
        AppFailure(code: 'invalid_pos_name', message: 'Point of sale name is required'),
      );
    }

    final pointOfSale = PointOfSale(
      id: ids.next('pos'),
      name: trimmed,
      status: PointOfSaleStatus.active,
      createdAt: clock.now(),
    );
    final saved = await pointsOfSale.save(pointOfSale);
    if (saved is Failure<void>) return Failure(saved.error);
    final audited = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'point_of_sale',
        entityId: pointOfSale.id,
        action: 'saved',
        occurredAt: clock.now(),
      ),
    );
    if (audited is Failure<void>) return Failure(audited.error);
    return Success(pointOfSale);
  }

  @override
  Future<Result<PointOfSale>> updatePointOfSale({
    required String id,
    required String name,
    required PointOfSaleStatus status,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Failure(
        AppFailure(code: 'invalid_pos_name', message: 'Point of sale name is required'),
      );
    }
    final found = await pointsOfSale.findById(id);
    if (found is Failure<PointOfSale?>) return Failure(found.error);
    final existing = (found as Success<PointOfSale?>).value;
    if (existing == null) {
      return const Failure(AppFailure(code: 'pos_not_found', message: 'Point of sale not found'));
    }
    final updated = PointOfSale(
      id: existing.id,
      name: trimmed,
      status: status,
      createdAt: existing.createdAt,
    );
    final saved = await pointsOfSale.save(updated);
    if (saved is Failure<void>) return Failure(saved.error);
    final audited = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'point_of_sale',
        entityId: updated.id,
        action: 'updated',
        occurredAt: clock.now(),
      ),
    );
    if (audited is Failure<void>) return Failure(audited.error);
    return Success(updated);
  }
}
