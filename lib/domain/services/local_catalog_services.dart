import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
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
        if (serial.isEmpty || secret.isEmpty) {
          return const Failure(
            AppFailure(
              code: 'invalid_card_import',
              message: 'Serial number and secret are required',
            ),
          );
        }

        final existingSerial = await cards.findBySerialNumber(serial);
        if (existingSerial is Failure<Card?>) return Failure(existingSerial.error);
        if ((existingSerial as Success<Card?>).value != null) {
          return const Failure(
            AppFailure(code: 'duplicate_serial', message: 'Card serial already exists'),
          );
        }

        final saved = await cards.save(
          Card(
            id: ids.next('card'),
            categoryId: categoryId,
            serialNumber: serial,
            secretCode: secret,
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
          payloadJson: '{"count":$imported}',
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(imported);
    });
  }
}

final class LocalWalletCatalogService implements WalletCatalogService {
  const LocalWalletCatalogService({
    required this.wallets,
    required this.auditLogs,
    required this.clock,
    required this.ids,
  });

  final WalletRepository wallets;
  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;

  @override
  Future<Result<Wallet>> saveWallet({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Failure(
        AppFailure(code: 'invalid_wallet_name', message: 'Wallet name is required'),
      );
    }

    final wallet = Wallet(
      id: ids.next('wallet'),
      name: trimmed,
      status: WalletStatus.active,
      createdAt: clock.now(),
    );
    final saved = await wallets.save(wallet);
    if (saved is Failure<void>) return Failure(saved.error);
    final audited = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'wallet',
        entityId: wallet.id,
        action: 'saved',
        occurredAt: clock.now(),
      ),
    );
    if (audited is Failure<void>) return Failure(audited.error);
    return Success(wallet);
  }

  @override
  Future<Result<Wallet>> updateWallet({
    required String id,
    required String name,
    required WalletStatus status,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Failure(
        AppFailure(code: 'invalid_wallet_name', message: 'Wallet name is required'),
      );
    }
    final found = await wallets.findById(id);
    if (found is Failure<Wallet?>) return Failure(found.error);
    final existing = (found as Success<Wallet?>).value;
    if (existing == null) {
      return const Failure(AppFailure(code: 'wallet_not_found', message: 'Wallet not found'));
    }
    final updated = Wallet(
      id: existing.id,
      name: trimmed,
      status: status,
      createdAt: existing.createdAt,
    );
    final saved = await wallets.save(updated);
    if (saved is Failure<void>) return Failure(saved.error);
    final audited = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'wallet',
        entityId: updated.id,
        action: 'updated',
        occurredAt: clock.now(),
      ),
    );
    if (audited is Failure<void>) return Failure(audited.error);
    return Success(updated);
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
