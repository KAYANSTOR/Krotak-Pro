import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../ledger.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';
import 'outbound_template_renderer.dart';

final class LocalCustomerBalanceService implements CustomerBalanceService {
  const LocalCustomerBalanceService({
    required this.customers,
    required this.transactions,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.advances,
    this.messageSender,
    this.settings,
  });

  final CustomerRepository customers;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;
  final AdvanceRepository? advances;
  final MessageSender? messageSender;
  final SettingsRepository? settings;

  static const _sellableStatuses = {
    CustomerStatus.active,
    CustomerStatus.provisional,
  };

  @override
  Future<Result<Money>> getBalance({
    required String customerId,
    required String currencyCode,
  }) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    try {
      return Success(
        sumCompletedLedger(
          transactions: (rows as Success<List<Transaction>>).value,
          currencyCode: currencyCode,
        ),
      );
    } on MixedCurrencyLedger {
      return const Failure(
        AppFailure(
          code: 'mixed_currency',
          message: 'Customer ledger contains mixed currencies',
        ),
      );
    }
  }

  @override
  Future<Result<Money>> getTotalOutstanding({required String currencyCode}) async {
    final rows = await transactions.listCompleted(currencyCode: currencyCode);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    try {
      return Success(
        sumCompletedLedger(
          transactions: (rows as Success<List<Transaction>>).value,
          currencyCode: currencyCode,
        ),
      );
    } on MixedCurrencyLedger {
      return const Failure(
        AppFailure(
          code: 'mixed_currency',
          message: 'Ledger contains mixed currencies',
        ),
      );
    }
  }

  @override
  Future<Result<CustomerAccountSummary>> getAccountSummary({
    required String customerId,
    required String currencyCode,
  }) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    final all = (rows as Success<List<Transaction>>).value;
    final completed = all
        .where((t) => t.status == TransactionStatus.completed)
        .toList(growable: false);

    Money balance;
    try {
      balance = sumCompletedLedger(
        transactions: completed,
        currencyCode: currencyCode,
      );
    } on MixedCurrencyLedger {
      return const Failure(
        AppFailure(
          code: 'mixed_currency',
          message: 'Customer ledger contains mixed currencies',
        ),
      );
    }

    var sales = 0;
    var deposits = 0;
    var withdrawals = 0;
    var settlements = 0;
    for (final t in completed) {
      if (t.amount.currencyCode != currencyCode) continue;
      switch (t.type) {
        case TransactionType.sale:
          sales += t.amount.minorUnits;
        case TransactionType.deposit:
        case TransactionType.reward:
          deposits += t.amount.minorUnits;
        case TransactionType.withdrawal:
          withdrawals += t.amount.minorUnits;
        case TransactionType.settlement:
          settlements += t.amount.minorUnits;
        case TransactionType.advance:
        case TransactionType.reversal:
          break;
      }
    }

    var openCount = 0;
    var openMinor = 0;
    final advRepo = advances;
    if (advRepo != null) {
      final adv = await advRepo.listByCustomer(customerId);
      if (adv is Success<List<Advance>>) {
        for (final a in adv.value) {
          if (a.status == AdvanceStatus.open &&
              a.amount.currencyCode == currencyCode) {
            openCount++;
            openMinor += a.amount.minorUnits;
          }
        }
      }
    }

    return Success(
      CustomerAccountSummary(
        balance: balance,
        totalSalesMinor: sales,
        totalDepositsMinor: deposits,
        totalWithdrawalsMinor: withdrawals,
        totalSettlementsMinor: settlements,
        openAdvancesCount: openCount,
        openAdvancesMinor: openMinor,
        transactionCount: completed.length,
      ),
    );
  }

  @override
  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
    String? reason,
  }) {
    return _adjust(
      customerId: customerId,
      amount: amount,
      reference: reference,
      reason: reason,
      type: TransactionType.deposit,
      auditAction: 'balance_credit',
    );
  }

  @override
  Future<Result<Transaction>> debit({
    required String customerId,
    required Money amount,
    String? reference,
    String? reason,
  }) {
    return _adjust(
      customerId: customerId,
      amount: amount,
      reference: reference,
      reason: reason,
      type: TransactionType.withdrawal,
      auditAction: 'balance_debit',
    );
  }

  Future<Result<Transaction>> _adjust({
    required String customerId,
    required Money amount,
    required TransactionType type,
    required String auditAction,
    String? reference,
    String? reason,
  }) async {
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_amount',
            message: 'Amount must be positive',
          ),
        ),
      );
    }

    final note = (reason ?? '').trim();
    var notifyDebtPayment = false;

    final result = await unitOfWork.run<Transaction>(() async {
      if (reference != null && reference.isNotEmpty) {
        final existing = await transactions.findByReference(reference);
        if (existing is Failure<Transaction?>) return Failure(existing.error);
        final current = (existing as Success<Transaction?>).value;
        if (current != null) {
          if (current.customerId == customerId &&
              current.amount == amount &&
              current.type == type) {
            return Success(current);
          }
          return const Failure(
            AppFailure(
              code: 'duplicate_reference',
              message: 'Reference already exists',
            ),
          );
        }
      }

      if (type == TransactionType.deposit) {
        final before = await getBalance(
          customerId: customerId,
          currencyCode: amount.currencyCode,
        );
        notifyDebtPayment =
            before is Success<Money> && before.value.minorUnits < 0;
      }

      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (!_sellableStatuses.contains(customer.status)) {
        return const Failure(
          AppFailure(
            code: 'customer_not_adjustable',
            message: 'Only active or provisional accounts can be adjusted',
          ),
        );
      }

      final transaction = Transaction(
        id: ids.next('txn'),
        type: type,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now(),
        customerId: customerId,
        reference: reference,
      );
      final appended = await transactions.append(transaction);
      if (appended is Failure<void>) return Failure(appended.error);

      final payload = StringBuffer('{"customerId":"$customerId"');
      payload.write(',"type":"${type.name}"');
      payload.write(',"amountMinor":${amount.minorUnits}');
      if (note.isNotEmpty) {
        payload.write(',"reason":"${_escape(note)}"');
      }
      payload.write('}');

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'customer',
          entityId: customerId,
          action: auditAction,
          payloadJson: payload.toString(),
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(transaction);
    });
    if (notifyDebtPayment && result is Success<Transaction>) {
      await _notifyDebtPayment(customerId: customerId, amount: amount);
    }
    return result;
  }

  Future<void> _notifyDebtPayment({
    required String customerId,
    required Money amount,
  }) async {
    final sender = messageSender;
    if (sender == null) return;
    final idsResult = await customers.listIdentifiers(customerId);
    if (idsResult is! Success<List<CustomerIdentifier>>) return;
    final phone = idsResult.value
        .where((i) => i.type == CustomerIdentifierType.phoneNumber)
        .map((i) => i.value.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (phone.isEmpty) return;
    final balance = await getBalance(
      customerId: customerId,
      currencyCode: amount.currencyCode,
    );
    if (balance is! Success<Money>) return;
    final found = await settings?.find(SettingKeys.customerDebtPaymentTemplate);
    final raw = found is Success<AppSetting?> ? found.value?.value : null;
    final rendered = OutboundTemplateRenderer.renderStrict(
      template: raw?.trim().isNotEmpty == true
          ? raw!
          : SettingDefaults.customerDebtPaymentTemplate,
      values: {
        'amount': _money(amount),
        'balance': _money(balance.value),
        'CURRENCY': amount.currencyCode,
        'currency': amount.currencyCode,
      },
    );
    if (rendered is Failure<String>) {
      await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'customer',
        entityId: customerId,
        action: 'debt_payment_sms_template_failed',
        payloadJson: '{"error":"${_escape(rendered.error.message)}"}',
        occurredAt: clock.now(),
      ));
      return;
    }
    final sent = await sender.send(
      destination: phone,
      body: (rendered as Success<String>).value,
    );
    await auditLogs.append(AuditLog(
      id: ids.next('audit'),
      entityType: 'customer',
      entityId: customerId,
      action: sent is Success<void>
          ? 'debt_payment_sms_sent'
          : 'debt_payment_sms_failed',
      payloadJson: '{"destination":"${_escape(phone)}"}',
      occurredAt: clock.now(),
    ));
  }

  String _money(Money money) => (money.minorUnits / 100).toStringAsFixed(2);

  static String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
