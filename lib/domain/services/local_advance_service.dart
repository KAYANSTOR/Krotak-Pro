import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'outbound_template_renderer.dart';
import 'services.dart';
import 'local_pos_account_registry.dart';

final class LocalAdvanceService implements AdvanceService {
  const LocalAdvanceService({required this.advances, required this.customers, required this.categories, required this.cards, required this.inventory, required this.transactions, required this.sales, required this.auditLogs, required this.settings, required this.unitOfWork, required this.messageSender, required this.clock, required this.ids, this.posRegistry});

  static const activationKey = SettingKeys.salafniEnabled;
  static const acceptedTemplateKey = SettingKeys.salafniAcceptedTemplate;
  static const rejectedTemplateKey = SettingKeys.salafniRejectedTemplate;
  static const settledTemplateKey = SettingKeys.salafniSettledTemplate;
  static const defaultAccepted = 'تم تفعيل سلفني بقيمة {amount} ريال. الكرت: {serial} | الرمز: {code}';
  static const defaultRejected = 'تعذر تنفيذ سلفني: {reason}';
  static const defaultSettled = 'تم تسديد سلفني بقيمة {amount} ريال. المتبقي من السلفة: {remaining} ريال.';

  final AdvanceRepository advances;
  final CustomerRepository customers;
  final CardCategoryRepository categories;
  final CardRepository cards;
  final CardInventoryService inventory;
  final TransactionRepository transactions;
  final SaleRepository sales;
  final AuditLogRepository auditLogs;
  final SettingsRepository settings;
  final UnitOfWork unitOfWork;
  final MessageSender messageSender;
  final Clock clock;
  final IdGenerator ids;
  final LocalPosAccountRegistry? posRegistry;

  @override
  Future<Result<AdvanceIssue>> request({required String customerId, required String currencyCode, required String operationId}) async {
    final enabledResult = await _isEnabled();
    if (enabledResult is Failure<bool>) return Failure(enabledResult.error);
    if (!(enabledResult as Success<bool>).value) return _reject('salafni_disabled', 'خدمة سلفني غير مفعلة', customerId: customerId);
    final op = operationId.trim();
    if (op.isEmpty) return _reject('invalid_operation_id', 'مرجع العملية فارغ', customerId: customerId);

    final existing = await transactions.findByReference('salafni:$op');
    if (existing is Failure<Transaction?>) return Failure(existing.error);
    final existingTx = (existing as Success<Transaction?>).value;
    if (existingTx != null && existingTx.type == TransactionType.advance) {
      final existingAdvance = await advances.findById(existingTx.id);
      if (existingAdvance is Failure<Advance?>) return Failure(existingAdvance.error);
      final existingValue = (existingAdvance as Success<Advance?>).value;
      if (existingValue != null) {
        final card = await cards.findById(existingValue.cardId);
        if (card is Failure<Card?>) return Failure(card.error);
        final cardValue = (card as Success<Card?>).value;
        if (cardValue != null) return Success(AdvanceIssue(advance: existingValue, card: cardValue));
      }
    }

    final customerResult = await customers.findById(customerId);
    if (customerResult is Failure<Customer?>) return Failure(customerResult.error);
    final customer = (customerResult as Success<Customer?>).value;
    if (customer == null) return _reject('customer_not_found', 'العميل غير موجود', customerId: customerId);
    if (customer.status != CustomerStatus.active) return _reject('customer_not_active', 'العميل غير نشط', customerId: customerId);

    // سلفني للعملاء فقط — نقاط البيع لها نظام دين مستقل بسقف.
    if (posRegistry != null) {
      final posLink = await posRegistry!.findByCustomerId(customerId);
      if (posLink is Failure) return Failure((posLink as Failure).error);
      if ((posLink as Success).value != null) {
        return _reject(
          'salafni_pos_not_allowed',
          'سلفني غير متاحة لنقاط البيع',
          customerId: customerId,
        );
      }
    }

    final open = await advances.findOpenByCustomer(customerId: customerId, currencyCode: currencyCode);
    if (open is Failure<Advance?>) return Failure(open.error);
    if ((open as Success<Advance?>).value != null) return _reject('advance_already_open', 'لدى العميل سلفة غير مسددة', customerId: customerId);

    final balance = await _balance(customerId, currencyCode);
    if (balance is Failure<Money>) return Failure(balance.error);
    if ((balance as Success<Money>).value.minorUnits != 0) return _reject('balance_not_zero', 'يجب أن يكون الرصيد صفرًا تمامًا', customerId: customerId);

    final categoryResult = await categories.listAll();
    if (categoryResult is Failure<List<CardCategory>>) return Failure(categoryResult.error);
    final active = (categoryResult as Success<List<CardCategory>>).value.where((c) => c.isActive && c.faceValue.currencyCode == currencyCode).toList(growable: false)
      ..sort((a, b) => a.faceValue.minorUnits.compareTo(b.faceValue.minorUnits));
    if (active.isEmpty) return _reject('no_active_category', 'لا توجد فئة كروت نشطة', customerId: customerId);

    CardCategory? selectedCategory;
    for (final category in active) {
      final available = await cards.findAvailableByCategory(category.id);
      if (available is Failure<List<Card>>) return Failure(available.error);
      if ((available as Success<List<Card>>).value.isNotEmpty) {
        selectedCategory = category;
        break;
      }
    }
    if (selectedCategory == null) return _reject('salafni_out_of_stock', 'لا يوجد كرت متاح في الفئات النشطة', customerId: customerId);

    final now = clock.now();
    final reservationId = ids.next('salafni-reservation');
    final reserved = await inventory.reserveAvailableCard(categoryId: selectedCategory.id, reservationId: reservationId, now: now, expiresAt: now.add(const Duration(minutes: 5)));
    if (reserved is Failure<Card>) return Failure(reserved.error);
    final selectedCard = (reserved as Success<Card>).value;

    final advanceId = ids.next('advance');
    final advanceTx = Transaction(id: advanceId, type: TransactionType.advance, status: TransactionStatus.completed, amount: selectedCategory.faceValue, createdAt: now, customerId: customerId, reference: 'salafni:$op');
    final append = await transactions.append(advanceTx);
    if (append is Failure<void>) {
      await cards.releaseReservation(selectedCard.id, reservationId);
      return Failure(append.error);
    }

    final sale = Sale(id: advanceId, customerId: customerId, cardId: selectedCard.id, amount: selectedCategory.faceValue, status: TransactionStatus.completed, createdAt: now);
    final marked = await cards.markSold(selectedCard.id, advanceId);
    if (marked is Failure<void>) return Failure(marked.error);
    final saleSaved = await sales.save(sale);
    if (saleSaved is Failure<void>) return Failure(saleSaved.error);

    final audit = await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'advance', entityId: advanceId, action: 'issued', occurredAt: now, payloadJson: '{"customerId":"$customerId","cardId":"${selectedCard.id}","operationId":"${_escape(op)}"}'));
    if (audit is Failure<void>) return Failure(audit.error);

    // Card is already committed (sold + ledger + sale). Delivery is best-effort:
    // never reverse the issue if SMS fails — resend / operator can retry.
    final issued = AdvanceIssue(
      advance: Advance(
        id: advanceId,
        customerId: customerId,
        cardId: selectedCard.id,
        amount: selectedCategory.faceValue,
        outstanding: selectedCategory.faceValue,
        reference: advanceTx.reference!,
        createdAt: now,
        status: AdvanceStatus.open,
      ),
      card: selectedCard,
    );
    final destination = await _deliveryPhone(customerId);
    if (destination.isEmpty) {
      await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'advance',
        entityId: advanceId,
        action: 'delivery_failed',
        occurredAt: clock.now(),
        payloadJson: '{"error":"delivery_phone_missing"}',
      ));
      return Success(issued);
    }
    final body = await _render(
      acceptedTemplateKey,
      defaultAccepted,
      {
        'amount': _money(selectedCategory.faceValue),
        'serial': selectedCard.serialNumber,
        'code': selectedCard.secretCode,
      },
    );
    Result<void>? send;
    if (body.trim().isNotEmpty) {
      send = await messageSender.send(destination: destination, body: body);
    }
    if (send is Failure<void>) {
      await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'advance',
        entityId: advanceId,
        action: 'delivery_failed',
        occurredAt: clock.now(),
        payloadJson:
            '{"error":"${_escape(send.error.message)}","destination":"${_escape(destination)}"}',
      ));
      return Success(issued);
    }
    await auditLogs.append(AuditLog(
      id: ids.next('audit'),
      entityType: 'advance',
      entityId: advanceId,
      action: 'delivery_succeeded',
      occurredAt: clock.now(),
      payloadJson: '{"destination":"${_escape(destination)}"}',
    ));
    return Success(issued);
  }

  @override
  Future<Result<AdvanceIssue>> requestByIdentifier({required String identifier, required String currencyCode, required String operationId}) async {
    final value = PhoneNormalizer.canonicalize(identifier) ?? identifier.trim();
    final customerResult = await customers.findByIdentifier(value);
    if (customerResult is Failure<Customer?>) return Failure(customerResult.error);
    final customer = (customerResult as Success<Customer?>).value;
    if (customer == null) return _reject('customer_not_found', 'العميل غير موجود', destination: PhoneNormalizer.isPhoneLike(identifier) ? value : null);
    return request(customerId: customer.id, currencyCode: currencyCode, operationId: operationId);
  }

  @override
  Future<Result<AdvancePaymentResult>> applyPayment({required String customerId, required Money amount, required String reference}) async {
    if (amount.minorUnits <= 0) return const Failure(AppFailure(code: 'invalid_amount', message: 'مبلغ السداد يجب أن يكون موجبًا'));
    final txResult = await transactions.findByCustomer(customerId);
    if (txResult is Failure<List<Transaction>>) return Failure(txResult.error);
    final allTransactions = (txResult as Success<List<Transaction>>).value;
    final prefix = 'salafni-settlement:$reference:';
    final priorPayments = allTransactions.where((t) => t.status == TransactionStatus.completed && t.type == TransactionType.deposit && (t.reference ?? '').startsWith(prefix)).toList(growable: false);
    var priorApplied = 0;
    Transaction? lastSettlement;
    for (final payment in priorPayments) {
      priorApplied += payment.amount.minorUnits;
      lastSettlement = payment;
    }
    if (priorApplied > amount.minorUnits) return const Failure(AppFailure(code: 'settlement_reference_conflict', message: 'مرجع السداد استُخدم بمبلغ أكبر سابقًا'));

    final list = await advances.listByCustomer(customerId);
    if (list is Failure<List<Advance>>) return Failure(list.error);
    final open = (list as Success<List<Advance>>).value.where((a) => a.status == AdvanceStatus.open && a.amount.currencyCode == amount.currencyCode).toList(growable: false);
    final outstandingTotal = open.fold<int>(0, (sum, advance) => sum + advance.outstanding.minorUnits);
    final firstAttemptRemaining = amount.minorUnits - priorApplied;
    if (priorApplied == 0 && outstandingTotal > 0 && firstAttemptRemaining > outstandingTotal) {
      final residual = firstAttemptRemaining - outstandingTotal;
      final categoriesResult = await categories.listAll();
      if (categoriesResult is Failure<List<CardCategory>>) return Failure(categoriesResult.error);
      final matches = (categoriesResult as Success<List<CardCategory>>).value.where((c) => c.isActive && c.faceValue.currencyCode == amount.currencyCode && c.faceValue.minorUnits == residual).toList(growable: false);
      if (matches.length != 1) return Success(AdvancePaymentResult(applied: Money(minorUnits: 0, currencyCode: amount.currencyCode), remaining: amount, settlementTransaction: null));
    }

    var remaining = firstAttemptRemaining;
    var applied = priorApplied;
    for (final advance in open) {
      if (remaining <= 0) break;
      final pay = remaining > advance.outstanding.minorUnits ? advance.outstanding.minorUnits : remaining;
      final payment = Transaction(id: ids.next('txn'), type: TransactionType.deposit, status: TransactionStatus.completed, amount: Money(minorUnits: pay, currencyCode: amount.currencyCode), createdAt: clock.now(), customerId: customerId, reference: '$prefix${advance.id}', relatedTransactionId: advance.id);
      final saved = await transactions.append(payment);
      if (saved is Failure<void>) return Failure(saved.error);
      lastSettlement = payment;
      applied += pay;
      remaining -= pay;
      final nowRemaining = advance.outstanding.minorUnits - pay;
      await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'advance', entityId: advance.id, action: nowRemaining <= 0 ? 'settled' : 'partially_settled', occurredAt: clock.now(), payloadJson: '{"paymentReference":"${_escape(reference)}","applied":$pay,"remaining":$nowRemaining}'));
      final destination = await _deliveryPhone(customerId);
      if (destination.isNotEmpty) {
        await messageSender.send(destination: destination, body: await _render(settledTemplateKey, defaultSettled, {'amount': _money(Money(minorUnits: pay, currencyCode: amount.currencyCode)), 'remaining': _money(Money(minorUnits: nowRemaining, currencyCode: amount.currencyCode))}));
      }
    }
    return Success(AdvancePaymentResult(applied: Money(minorUnits: applied, currencyCode: amount.currencyCode), remaining: Money(minorUnits: remaining, currencyCode: amount.currencyCode), settlementTransaction: lastSettlement));
  }

  @override
  Future<Result<List<Advance>>> listCustomerAdvances(String customerId) => advances.listByCustomer(customerId);

  Future<Result<bool>> _isEnabled() async {
    final result = await settings.find(activationKey);
    if (result is Failure<AppSetting?>) return Failure(result.error);
    final raw = (result as Success<AppSetting?>).value?.value.trim().toLowerCase();
    return Success(raw == 'true' || raw == '1');
  }

  Future<Result<Money>> _balance(String customerId, String currencyCode) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    var total = 0;
    for (final row in (rows as Success<List<Transaction>>).value) {
      if (row.status != TransactionStatus.completed || row.amount.currencyCode != currencyCode) continue;
      total += switch (row.type) {
        TransactionType.deposit || TransactionType.reward || TransactionType.reversal => row.amount.minorUnits,
        TransactionType.withdrawal || TransactionType.sale || TransactionType.settlement || TransactionType.advance => -row.amount.minorUnits,
      };
    }
    return Success(Money(minorUnits: total, currencyCode: currencyCode));
  }

  Future<String> _deliveryPhone(String customerId) async {
    final idsResult = await customers.listIdentifiers(customerId);
    if (idsResult is Failure<List<CustomerIdentifier>>) return '';
    final identifiers = (idsResult as Success<List<CustomerIdentifier>>).value.where((i) => i.type == CustomerIdentifierType.phoneNumber).toList(growable: false);
    if (identifiers.isEmpty) return '';
    final primary = identifiers.where((i) => i.isPrimary).firstOrNull ?? identifiers.first;
    return PhoneNormalizer.canonicalize(primary.value) ?? primary.value;
  }

  Future<String> _render(String key, String fallback, Map<String, String> values) async {
    final result = await settings.find(key);
    final template = result is Success<AppSetting?> &&
            result.value?.value.trim().isNotEmpty == true
        ? result.value!.value
        : fallback;
    final rendered = OutboundTemplateRenderer.renderStrict(
      template: template,
      values: values,
    );
    if (rendered is Failure<String>) {
      // Prefer not to send broken placeholders; return empty so caller can skip send.
      return '';
    }
    return (rendered as Success<String>).value;
  }

  String _money(Money money) => (money.minorUnits / 100).toStringAsFixed(2);

  Future<Result<AdvanceIssue>> _reject(String code, String message, {String? customerId, String? destination}) async {
    final target = customerId == null ? destination : await _deliveryPhone(customerId);
    if (target != null && target.trim().isNotEmpty) {
      final body = await _render(rejectedTemplateKey, defaultRejected, {'reason': message});
      if (body.trim().isNotEmpty) {
        await messageSender.send(destination: target, body: body);
      }
    }
    await auditLogs.append(AuditLog(id: ids.next('audit'), entityType: 'advance_request', entityId: customerId ?? destination ?? 'unknown', action: 'rejected', occurredAt: clock.now(), payloadJson: '{"code":"${_escape(code)}","reason":"${_escape(message)}"}'));
    return Failure(AppFailure(code: code, message: message));
  }

  String _escape(String value) => value.replaceAll('"', '\\"').replaceAll('\n', ' ');
}
