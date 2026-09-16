import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_promotion_catalog.dart';
import 'local_promotion_progress_service.dart';
import 'services.dart';

/// صرف مكافأة العرض عند بلوغ العتبة — دورة لكل مضاعف للعتبة.
///
/// المرجع المستقر: `promo-reward:{promoId}:{customerId}:{cycle}`
/// حركة الدفتر من نوع `reward` حتى لا تدخل في تراكم المبيعات.
/// إرسال SMS بعد الصرف لا يعيد البيع إن فشل.
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
    required this.customers,
    required this.settings,
    this.messageSender,
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
  final CustomerRepository customers;
  final SettingsRepository settings;
  final MessageSender? messageSender;

  static const defaultRewardSmsTemplate =
      SettingDefaults.promotionRewardSmsTemplate;

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
        final cycles =
            item.accumulatedMinor ~/ item.promotion.thresholdMinorUnits;
        if (cycles <= 0) continue;
        for (var cycle = 1; cycle <= cycles; cycle++) {
          final reference = rewardReference(
            promotionId: item.promotion.id,
            customerId: customerId,
            cycle: cycle,
          );
          final existing = await transactions.findByReference(reference);
          if (existing is Failure<Transaction?>) {
            return Failure(existing.error);
          }
          if ((existing as Success<Transaction?>).value != null) continue;

          final sale = await _awardCycle(
            customerId: customerId,
            promotionId: item.promotion.id,
            promotionTitle: item.promotion.title,
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
    required String promotionTitle,
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

    await _notifyReward(
      customerId: customerId,
      promotionId: promotionId,
      promotionTitle: promotionTitle,
      card: card,
      amountMinor: category.faceValue.minorUnits,
    );
    return Success(sale);
  }

  Future<void> _notifyReward({
    required String customerId,
    required String promotionId,
    required String promotionTitle,
    required Card card,
    required int amountMinor,
  }) async {
    final sender = messageSender;
    if (sender == null) return;
    final destination = await _deliveryPhone(customerId);
    if (destination.isEmpty) {
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'promotion',
          entityId: promotionId,
          action: 'reward_sms_skipped',
          payloadJson: '{"customerId":"$customerId","reason":"no_phone"}',
          occurredAt: clock.now(),
        ),
      );
      return;
    }
    final body = await _renderTemplate({
      'title': promotionTitle,
      'serial': card.serialNumber,
      'secret': card.secretCode,
      'code': card.secretCode,
      'amount': (amountMinor / 100).toStringAsFixed(2),
    });
    final sent = await sender.send(destination: destination, body: body);
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'promotion',
        entityId: promotionId,
        action: sent is Success<void> ? 'reward_sms_sent' : 'reward_sms_failed',
        payloadJson:
            '{"customerId":"$customerId","destination":"$destination","ok":${sent is Success<void>}}',
        occurredAt: clock.now(),
      ),
    );
  }

  Future<String> _deliveryPhone(String customerId) async {
    final idsResult = await customers.listIdentifiers(customerId);
    if (idsResult is Failure<List<CustomerIdentifier>>) return '';
    final phones = (idsResult as Success<List<CustomerIdentifier>>)
        .value
        .where((i) => i.type == CustomerIdentifierType.phoneNumber)
        .toList(growable: false);
    if (phones.isEmpty) return '';
    final primary =
        phones.where((i) => i.isPrimary).firstOrNull ?? phones.first;
    return PhoneNormalizer.canonicalize(primary.value) ?? primary.value;
  }

  Future<String> _renderTemplate(Map<String, String> values) async {
    final result = await settings.find(SettingKeys.promotionRewardSmsTemplate);
    final raw = result is Success<AppSetting?> ? result.value?.value : null;
    var output = (raw != null && raw.trim().isNotEmpty)
        ? raw
        : defaultRewardSmsTemplate;
    values.forEach((name, value) {
      output = output.replaceAll('{$name}', value);
    });
    return output;
  }
}
