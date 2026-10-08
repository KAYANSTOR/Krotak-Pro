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
import 'outbound_template_renderer.dart';
import 'promotion_reward_template.dart';
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

  /// النص الأولي لقالب مكافأة العرض — موجود في العقد المركزي وحده.
  /// لا يُستخدم وقت الإرسال: الإرسال يقرأ من الإعدادات حصرًا.
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
    final holds = await settings.find(SettingKeys.promotionRewardProbeHolds);
    if (holds is Failure<AppSetting?>) return Failure(holds.error);
    final holdRaw = (holds as Success<AppSetting?>).value?.value;
    final held = await _claimProbeHold(
      categoryId: categoryId,
      customerId: customerId,
      raw: holdRaw,
      now: now,
    );
    if (held is Failure<Card?>) return Failure(held.error);
    final claimed = (held as Success<Card?>).value;
    final Card card;
    if (claimed != null) {
      card = claimed;
    } else {
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
      card = (reserved as Success<Card>).value;
    }
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
    final consumed = (held as Success<Card?>).value == null
        ? null
        : PromotionRewardTemplate.claimHold(
            holdRaw,
            categoryId,
            now,
            customerId: customerId,
          );
    if (consumed != null) {
      final cleared = await settings.save(
        AppSetting(
          key: SettingKeys.promotionRewardProbeHolds,
          value: PromotionRewardTemplate.consumeHold(
            holdRaw,
            categoryId,
            customerId: consumed.customerId,
            cardId: card.id,
          ),
          updatedAt: now,
        ),
      );
      if (cleared is Failure<void>) return Failure(cleared.error);
    }

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
    final amount = (amountMinor / 100).toStringAsFixed(2);
    final customer = await customers.findById(customerId);
    final customerName = customer is Success<Customer?>
        ? (customer.value?.displayName ?? '')
        : '';
    final rendered = await _renderTemplate(promotionId, customerId, {
      'title': promotionTitle,
      'promotion_name': promotionTitle,
      'serial': card.serialNumber,
      'secret': card.secretCode,
      'code': card.secretCode,
      'amount': amount,
      'reward_value': amount,
      'customer_name': customerName,
    });
    if (rendered is Failure<String>) {
      // لا إرسال بلا قالب مسجّل — نُسجّل السبب ونكتفي بالكرت المصروف.
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'promotion',
          entityId: promotionId,
          action: 'reward_sms_skipped',
          payloadJson:
              '{"customerId":"$customerId","reason":"${rendered.error.code}"}',
          occurredAt: clock.now(),
        ),
      );
      return;
    }
    final body = (rendered as Success<String>).value;
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

  Future<Result<String>> _renderTemplate(
    String promotionId,
    String customerId,
    Map<String, String> values,
  ) async {
    final global = await settings.find(SettingKeys.promotionRewardSmsTemplate);
    final perOffer = await settings.find(SettingKeys.promotionRewardSmsTemplates);
    final perCustomer =
        await settings.find(SettingKeys.promotionRewardCustomerSmsTemplates);
    final perCustomerGlobal = await settings.find(
      SettingKeys.promotionRewardCustomerGlobalSmsTemplates,
    );
    final globalRaw = global is Success<AppSetting?> ? global.value?.value : null;
    final mapRaw = perOffer is Success<AppSetting?> ? perOffer.value?.value : null;
    final customerRaw =
        perCustomer is Success<AppSetting?> ? perCustomer.value?.value : null;
    final customerGlobalRaw = perCustomerGlobal is Success<AppSetting?>
        ? perCustomerGlobal.value?.value
        : null;
    // الطبقات الأخصّ (عميل داخل عرض → عميل عام) قد تحمل نصًّا مخصّصًا.
    final specific = PromotionRewardTemplate.resolveLayer(
      perCustomer: PromotionRewardTemplate.lookupCustomer(
        customerRaw,
        promotionId,
        customerId,
      ),
      perOffer: PromotionRewardTemplate.lookup(mapRaw, promotionId),
      perCustomerGlobal: PromotionRewardTemplate.lookupGlobalCustomer(
        customerGlobalRaw,
        customerId,
      ),
      global: globalRaw,
      fallback: '',
    );
    // لا يوجد نص في أي طبقة مخصّصة → القالب العام المسجّل في الإعدادات وحده.
    // لا نص بديل: إن غاب القالب العام فشل الإرسال.
    final resolved = specific.template.trim().isEmpty
        ? await OutboundTemplateRenderer(settings: settings).loadRegisteredBody(
            SettingKeys.promotionRewardSmsTemplate,
          )
        : Success(specific.template);
    if (resolved is Failure<String>) return Failure(resolved.error);
    return OutboundTemplateRenderer.renderStrict(
      template: (resolved as Success<String>).value,
      values: values,
    );
  }

  /// يستخدم حجز المعاينة إن كان الكرت ما يزال محجوزاً بنفس المعرّف. غير ذلك لا يحجز شيئاً هنا.
  Future<Result<Card?>> _claimProbeHold({
    required String categoryId,
    required String customerId,
    required String? raw,
    required DateTime now,
  }) async {
    final hold = PromotionRewardTemplate.claimHold(
      raw,
      categoryId,
      now,
      customerId: customerId,
    );
    if (hold == null) return const Success(null);
    for (final item in hold.cards) {
      final found = await cards.findById(item.cardId);
      if (found is Failure<Card?>) return Failure(found.error);
      final card = (found as Success<Card?>).value;
      final reservation = card?.reservation;
      if (card == null ||
          card.categoryId != categoryId ||
          card.status != CardStatus.reserved ||
          reservation?.reservationId != item.reservationId) {
        continue;
      }
      return Success(card);
    }
    return const Success(null);
  }
}
