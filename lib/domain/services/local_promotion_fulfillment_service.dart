import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';
import 'local_promotion_catalog.dart';
import 'local_promotion_progress_service.dart';

/// صرف مكافأة العرض عند بلوغ العتبة — دورة لكل مضاعف للعتبة.
///
/// المرجع المستقر: `promo-reward:{promoId}:{customerId}:{cycle}`
/// حركة الدفتر من نوع `reward` حتى لا تدخل في تراكم المبيعات.
final class LocalPromotionFulfillmentService {
  const LocalPromotionFulfillmentService({
    required this.progress,
    required this.promotions,
    required this.categories,
    required this.cards,
    required this.inventory,
    required this.sales,
    required this.transactions,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final LocalPromotionProgressService progress;
  final LocalPromotionCatalog promotions;
  final CardCategoryRepository categories;
  final CardRepository cards;
  final CardInventoryService inventory;
  final SaleRepository sales;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  static String rewardReference({
    required String promotionId,
    required String customerId,
    required int cycle,
  }) =>
      'promo-reward:$promotionId:$customerId:$cycle';

  Future<Result<List<Sale>>> fulfillQualified({
    required String customerId,
  }) {
    return unitOfWork.run(() async {
      final tracked = await progress.forCustomer(customerId);
      if (tracked is Failure<List<PromotionProgress>>) {
        return Failure(tracked.error);
      }
      final awarded = <Sale>[];
      for (final item in (tracked as Success<List<PromotionProgress>>).value) {
        if (!item.qualified) continue;
        final cycles = item.accumulatedMinor ~/ item.promotion.thresholdMinorUnits;
        if (cycles <= 0) continue;
        for (var cycle = 1; cycle <= cycles; cycle++) {
          final reference = rewardReference(
            promotionId: item.promotion.id,
            customerId: customerId,
            cycle: cycle,
          );
          final existing = await transactions.findByReference(reference);
          if (existing is Failure<Transaction?>) return Failure(existing.error);
          if ((existing as Success<Transaction?>).value != null) continue;

          final sale = await _awardCycle(
            customerId: customerId,
            promotionId: item.promotion.id,
            categoryId: item.promotion.rewardCategoryId,
            reference: reference,
          );
          if (sale is Failure<Sale>) return Failure(sale.error);
          awarded.add((sale as Success<Sale>).value);
        }
      }
      return Success(awarded);
    });
  }

  Future<Result<Sale>> _awardCycle({
    required String customerId,
    required String promotionId,
    required String categoryId,
    required String reference,
  }) async {
    final foundCategory = await categories.findById(categoryId);
    if (foundCategory is Failure<CardCategory?>) {
      return Failure(foundCategory.error);
    }
    final category = (foundCategory as Success<CardCategory?>).value;
    if (category == null) {
      return const Failure(
        AppFailure(
          code: 'reward_category_not_found',
          message: 'فئة مكافأة العرض غير موجودة',
        ),
      );
    }
    if (!category.isActive) {
      return const Failure(
        AppFailure(
          code: 'reward_category_inactive',
          message: 'فئة مكافأة العرض غير نشطة',
        ),
      );
    }

    final now = clock.now();
    final reserved = await inventory.reserveAvailableCard(
      categoryId: categoryId,
      reservationId: ids.next('promo-res'),
      now: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    if (reserved is Failure<Card>) {
      return Failure(
        AppFailure(
          code: 'reward_stock_unavailable',
          message: reserved.error.message,
        ),
      );
    }
    final card = (reserved as Success<Card>).value;
    final sale = Sale(
      id: ids.next('promo-sale'),
      customerId: customerId,
      cardId: card.id,
      amount: category.faceValue,
      status: TransactionStatus.completed,
      createdAt: now,
    );
    final marked = await cards.markSold(card.id, sale.id);
    if (marked is Failure<void>) return Failure(marked.error);

    final txn = Transaction(
      id: ids.next('promo-txn'),
      type: TransactionType.reward,
      status: TransactionStatus.completed,
      amount: category.faceValue,
      createdAt: now,
      customerId: customerId,
      reference: reference,
    );
    final appended = await transactions.append(txn);
    if (appended is Failure<void>) return Failure(appended.error);

    final saved = await sales.save(sale);
    if (saved is Failure<void>) return Failure(saved.error);

    final audited = await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'promotion',
        entityId: promotionId,
        action: 'reward_fulfilled',
        payloadJson:
            '{"customerId":"$customerId","saleId":"${sale.id}","cardId":"${card.id}","reference":"$reference"}',
        occurredAt: now,
      ),
    );
    if (audited is Failure<void>) return Failure(audited.error);
    return Success(sale);
  }
}
