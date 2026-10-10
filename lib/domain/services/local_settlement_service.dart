import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../ledger.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'outbound_template_renderer.dart';
import 'services.dart';

/// Settlement: debit completed balance for a customer (e.g. POS settlement).
///
/// Rules (temporary product assumptions):
/// - customer must be active
/// - amount must be positive and same currency as existing ledger
/// - available completed balance must cover the amount
/// - atomic: transaction append + audit
final class LocalSettlementService {
  const LocalSettlementService({
    required this.customers,
    required this.transactions,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.settings,
    this.messageSender,
  });

  final CustomerRepository customers;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  /// إعدادات القوالب — غيابها يُلغي رسالة تأكيد السداد ولا يمنع التسوية.
  final SettingsRepository? settings;

  /// إرسال الرسائل — غيابه يُلغي رسالة تأكيد السداد ولا يمنع التسوية.
  final MessageSender? messageSender;

  Future<Result<Transaction>> settle({
    required String customerId,
    required Money amount,
    String? reference,
  }) async {
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_amount', message: 'Settlement amount must be positive'),
        ),
      );
    }

    // النوع الصريح مهم: بلا <Transaction> يصبح T = dynamic ويرجع Failure<dynamic>
    // لا يمكن إرجاعه من دالة نوعها Result<Transaction>.
    final settled = await unitOfWork.run<Transaction>(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(code: 'customer_not_active', message: 'Only active customers can settle'),
        );
      }

      final rows = await transactions.findByCustomer(customerId);
      if (rows is Failure<List<Transaction>>) return Failure(rows.error);
      final ledger = (rows as Success<List<Transaction>>).value;

      final Money balance;
      try {
        balance = sumCompletedLedger(
          transactions: ledger,
          currencyCode: amount.currencyCode,
        );
      } on StateError catch (e) {
        return Failure(AppFailure(code: 'currency_mismatch', message: e.message));
      }

      if (balance.minorUnits < amount.minorUnits) {
        return const Failure(
          AppFailure(code: 'insufficient_balance', message: 'Balance does not cover settlement'),
        );
      }

      if (reference != null && reference.isNotEmpty) {
        final existing = await transactions.findByReference(reference);
        if (existing is Failure<Transaction?>) return Failure(existing.error);
        final prior = (existing as Success<Transaction?>).value;
        if (prior != null) {
          if (prior.customerId == customerId &&
              prior.amount.minorUnits == amount.minorUnits &&
              prior.amount.currencyCode == amount.currencyCode &&
              prior.type == TransactionType.settlement) {
            return Success(prior);
          }
          return const Failure(
            AppFailure(code: 'duplicate_reference', message: 'Settlement reference already used'),
          );
        }
      }

      final tx = Transaction(
        id: ids.next('tx'),
        type: TransactionType.settlement,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now(),
        customerId: customerId,
        reference: reference,
      );
      final saved = await transactions.append(tx);
      if (saved is Failure<void>) return Failure(saved.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'transaction',
          entityId: tx.id,
          action: 'settlement',
          payloadJson: '{"customerId":"$customerId","minorUnits":${amount.minorUnits}}',
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(tx);
    });
    // لا يُستخدم cast إلى Success: وحدة العمل قد ترجع Failure بنوع داخلي مختلف
    // (Failure<Object?>) عند التراجع، فالفحص النمطي هو الآمن هنا.
    if (settled is! Success<Transaction>) return settled;
    final transaction = settled.value;
    // الرسالة خارج الوحدة الذرّية: فشل الإرسال لا يُلغي تسوية مالية مكتملة.
    await _notifyDebtSettlement(transaction);
    return Success(transaction);
  }

  /// يرسل تأكيد سداد دين العميل من القالب المسجّل في الإعدادات.
  ///
  /// قرارات المالك §7: قالب `customer_debt_payment_template` كان مسجّلًا بلا أي
  /// مسار إرسال. هذا المسار — التسوية اليدوية من دفتر الحساب — هو مسار سداد دين
  /// العميل الفعلي، ويُمرَّر له المبلغ المسدَّد والمخصوم والفائض (صفر) والرصيد
  /// الجديد من نتيجة المعاملة الفعلية لا من نص الرسالة.
  ///
  /// العملية idempotent: إعادة استدعاء التسوية بنفس المرجع لا ترسل الرسالة مرتين
  /// (سجل تدقيق `customer_debt_settlement_notified` لكل معاملة)، وفشل الإرسال
  /// يُسجَّل في Audit ولا يعكس التسوية ولا يعيد المحاولة تلقائيًا.
  Future<void> _notifyDebtSettlement(Transaction transaction) async {
    final sender = messageSender;
    final settingsRepo = settings;
    final customerId = transaction.customerId;
    if (sender == null || settingsRepo == null) return;
    if (customerId == null || customerId.trim().isEmpty) return;
    if (await _alreadyNotified(transaction.id)) return;

    final destination = await _customerPhone(customerId);
    if (destination.isEmpty) {
      await _auditSettlement(
        transaction,
        'customer_debt_settlement_notify_skipped',
        'no_customer_phone',
      );
      return;
    }

    final currencyCode = transaction.amount.currencyCode;
    final balance = await _balanceAfter(customerId, currencyCode);
    final rendered =
        await OutboundTemplateRenderer(settings: settingsRepo).renderRegistered(
      key: SettingKeys.customerDebtPaymentTemplate,
      values: <String, String>{
        'amount': _majorAmountText(transaction.amount),
        'paid': _majorAmountText(transaction.amount),
        'surplus': '0',
        'balance': balance == null ? '0' : _majorAmountText(balance),
        'CURRENCY': currencyCode == 'YER' ? 'ر.ي' : currencyCode,
      },
    );
    if (rendered is Failure<String>) {
      await _auditSettlement(
        transaction,
        'customer_debt_settlement_notify_failed',
        rendered.error.code,
      );
      return;
    }

    final sent = await sender.send(
      destination: destination,
      body: (rendered as Success<String>).value,
    );
    await _auditSettlement(
      transaction,
      sent is Failure<void>
          ? 'customer_debt_settlement_notify_failed'
          : 'customer_debt_settlement_notified',
      sent is Failure<void> ? sent.error.code : null,
    );
  }

  Future<bool> _alreadyNotified(String transactionId) async {
    final logs = await auditLogs.findByEntity('transaction', transactionId);
    if (logs is Failure<List<AuditLog>>) return false;
    return (logs as Success<List<AuditLog>>)
        .value
        .any((log) => log.action == 'customer_debt_settlement_notified');
  }

  Future<String> _customerPhone(String customerId) async {
    final result = await customers.listIdentifiers(customerId);
    if (result is Failure<List<CustomerIdentifier>>) return '';
    final phones = (result as Success<List<CustomerIdentifier>>)
        .value
        .where((item) => item.type == CustomerIdentifierType.phoneNumber)
        .toList(growable: false);
    if (phones.isEmpty) return '';
    return phones.first.value.trim();
  }

  /// الرصيد المكتمل بعد التسوية، مقروءًا من الدفتر لا محسوبًا من نص الرسالة.
  Future<Money?> _balanceAfter(String customerId, String currencyCode) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return null;
    try {
      return sumCompletedLedger(
        transactions: (rows as Success<List<Transaction>>).value,
        currencyCode: currencyCode,
      );
    } on StateError {
      return null;
    }
  }

  Future<void> _auditSettlement(
    Transaction transaction,
    String action,
    String? detail,
  ) async {
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'transaction',
        entityId: transaction.id,
        action: action,
        occurredAt: clock.now(),
        payloadJson: jsonEncode(<String, Object?>{
          'customerId': transaction.customerId,
          'minorUnits': transaction.amount.minorUnits,
          'currency': transaction.amount.currencyCode,
          if (detail != null) 'detail': detail,
        }),
      ),
    );
  }

  static String _majorAmountText(Money money) {
    final major = money.minorUnits / 100;
    return major == major.roundToDouble()
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
  }
}
