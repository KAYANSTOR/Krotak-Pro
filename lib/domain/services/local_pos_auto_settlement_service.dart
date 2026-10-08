import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../ledger.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import 'local_pos_account_registry.dart';
import 'outbound_template_renderer.dart';
import 'services.dart';

/// Applies an incoming wallet transfer as a POS ledger settlement
/// when the beneficiary identifier matches an active point of sale.
///
/// Returns `null` when the transfer is not a POS settlement candidate
/// so the caller can continue the card-sale path.
final class LocalPosAutoSettlementService {
  const LocalPosAutoSettlementService({
    required this.posRegistry,
    required this.settings,
    required this.customers,
    required this.transactions,
    required this.balances,
    required this.messages,
    required this.auditLogs,
    required this.clock,
    required this.ids,
    this.templates,
    this.messageSender,
  });

  final LocalPosAccountRegistry posRegistry;
  final SettingsRepository settings;
  final CustomerRepository customers;
  final TransactionRepository transactions;
  final CustomerBalanceService balances;
  final MessageRepository messages;
  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;
  final TransferTemplateRepository? templates;
  final MessageSender? messageSender;

  Future<Result<Transaction>?> trySettle({
    required ParsedTransfer transfer,
    required IncomingMessage message,
  }) async {
    if (!await _enabled()) return null;
    if (await _isPosRequestTemplate(transfer.templateId)) return null;

    final accountResult = await _resolveAccount(transfer);
    if (accountResult is Failure<PosAccount?>) {
      return Failure<Transaction>(accountResult.error);
    }
    final account = (accountResult as Success<PosAccount?>).value;
    if (account == null) return null;
    if (account.status != PointOfSaleStatus.active) return null;

    final paymentRef = transfer.reference.trim().isEmpty
        ? transfer.messageId
        : transfer.reference.trim();
    final settleRef = 'pos-settle:${account.posId}:$paymentRef';

    final credited = await balances.credit(
      customerId: account.customerId,
      amount: transfer.amount,
      reference: settleRef,
    );
    if (credited is Failure<Transaction>) {
      await _notifyFailure(account, reason: credited.error.message);
      await messages.updateStatus(message.id, MessageProcessingStatus.failed);
      return Failure(credited.error);
    }
    final tx = (credited as Success<Transaction>).value;

    final remainingResult = await _remainingDebt(
      customerId: account.customerId,
      currencyCode: transfer.amount.currencyCode,
    );
    if (remainingResult is Failure<int>) {
      // لم نتمكن من التحقق من المتبقي: الرصيد أُضيف فعلًا، والحركة موثّقة،
      // لكن لا يجوز إرسال «تسوية ناجحة» برقم غير مؤكد — نُرسل إشعار «غير
      // مؤكدة» من قالبه المسجّل ونترك الرسالة للمراجعة اليدوية.
      await messages.updateStatus(message.id, MessageProcessingStatus.failed);
      await _notifyUnknown(account);
      return Failure(remainingResult.error);
    }
    final remaining = (remainingResult as Success<int>).value;

    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'pos_account',
        entityId: account.posId,
        action: 'settled',
        occurredAt: clock.now(),
        payloadJson:
            '{"posId":"${account.posId}","customerId":"${account.customerId}","minorUnits":${transfer.amount.minorUnits},"remainingDebt":$remaining,"reference":"$settleRef"}',
      ),
    );

    await messages.updateStatus(message.id, MessageProcessingStatus.processed);
    await _notifySuccess(account, amount: transfer.amount, remainingDebt: remaining);
    return Success(tx);
  }

  Future<bool> _enabled() async {
    final setting = await settings.find(SettingKeys.autoPosSettlementEnabled);
    if (setting is Failure<AppSetting?>) return true;
    return SettingBool.read(
      (setting as Success<AppSetting?>).value?.value,
      defaultValue: SettingDefaults.autoPosSettlementEnabled,
    );
  }

  Future<bool> _isPosRequestTemplate(String? templateId) async {
    if (templateId == null || templateId.isEmpty) return false;
    final repo = templates;
    if (repo == null) return false;
    final found = await repo.findById(templateId);
    if (found is! Success<TransferTemplate?>) return false;
    final tpl = found.value;
    return tpl != null && tpl.posId != null && tpl.posId!.isNotEmpty;
  }

  Future<Result<PosAccount?>> _resolveAccount(ParsedTransfer transfer) async {
    final identifier = transfer.customerIdentifier.trim();
    if (identifier.isEmpty) return const Success(null);

    if (transfer.posId != null && transfer.posId!.trim().isNotEmpty) {
      return posRegistry.findByPosId(transfer.posId!.trim());
    }

    final byId = await posRegistry.findByPosId(identifier);
    if (byId is Failure<PosAccount?>) return byId;
    if ((byId as Success<PosAccount?>).value != null) return byId;

    return posRegistry.findByIdentifier(identifier);
  }

  Future<Result<int>> _remainingDebt({
    required String customerId,
    required String currencyCode,
  }) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    try {
      final balance = sumCompletedLedger(
        transactions: (rows as Success<List<Transaction>>).value,
        currencyCode: currencyCode,
      );
      return Success(balance.minorUnits < 0 ? -balance.minorUnits : 0);
    } on Object catch (error) {
      // تعذّر جمع الدفتر: لا يجوز اعتبار المتبقي صفرًا وإرسال «تسوية ناجحة»
      // برقم غير صحيح — نُبلّغ الفشل ليتعامل معه المسار الأعلى.
      return Failure(
        AppFailure(
          code: 'pos_settlement_balance_unverified',
          message: 'تعذّر التحقق من رصيد نقطة البيع بعد التسوية: $error',
        ),
      );
    }
  }

  Future<void> _notifySuccess(
    PosAccount account, {
    required Money amount,
    required int remainingDebt,
  }) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final amountText = (amount.minorUnits / 100).toStringAsFixed(0);
    final remainingText = (remainingDebt / 100).toStringAsFixed(0);
    final rendered = await _render(
      SettingKeys.posSettlementSuccessTemplate,
      <String, String>{
        'pos': account.name,
        'pos_name': account.name,
        'POS_NAME': account.name,
        'amount': amountText,
        'SETTLEMENT_AMOUNT': amountText,
        'remaining': remainingText,
        'REMAINING_BALANCE': remainingText,
        'identifier':
            account.identifiers.isEmpty ? '' : account.identifiers.first,
        'CURRENCY': 'ر.ي',
      },
    );
    if (rendered is Failure<String>) return;
    await sender.send(
      destination: dest,
      body: (rendered as Success<String>).value,
    );
  }

  Future<void> _notifyFailure(PosAccount account, {required String reason}) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final rendered = await _render(
      SettingKeys.posSettlementFailedTemplate,
      <String, String>{
        'pos': account.name,
        'pos_name': account.name,
        'POS_NAME': account.name,
        'reason': reason,
      },
    );
    if (rendered is Failure<String>) return;
    await sender.send(
      destination: dest,
      body: (rendered as Success<String>).value,
    );
  }

  /// إشعار «تسوية غير مؤكدة» — كان قالبه معروضًا في الإعدادات بلا مستهلك.
  Future<void> _notifyUnknown(PosAccount account) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final rendered = await _render(
      SettingKeys.posSettlementUnknownTemplate,
      <String, String>{
        'pos': account.name,
        'pos_name': account.name,
        'POS_NAME': account.name,
      },
    );
    if (rendered is Failure<String>) return;
    await sender.send(
      destination: dest,
      body: (rendered as Success<String>).value,
    );
  }

  /// إشعار رفض طلب نقطة البيع — كان قالبه معروضًا في الإعدادات بلا مستهلك.
  Future<void> notifyRequestRejected(
    PosAccount account, {
    required String reason,
  }) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final rendered = await _render(
      SettingKeys.posRequestRejectedTemplate,
      <String, String>{
        'pos': account.name,
        'pos_name': account.name,
        'POS_NAME': account.name,
        'reason': reason,
      },
    );
    if (rendered is Failure<String>) return;
    await sender.send(
      destination: dest,
      body: (rendered as Success<String>).value,
    );
  }

  /// إشعار تجاوز سقف الدين — كان قالبه معروضًا في الإعدادات بلا مستهلك.
  Future<void> notifyCreditLimitExceeded(PosAccount account) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final rendered = await _render(
      SettingKeys.posCreditLimitExceededTemplate,
      <String, String>{
        'pos': account.name,
        'pos_name': account.name,
        'POS_NAME': account.name,
        'limit': ((account.creditLimitMinorUnits ?? 0) / 100).toStringAsFixed(0),
        'CURRENCY': 'ر.ي',
      },
    );
    if (rendered is Failure<String>) return;
    await sender.send(
      destination: dest,
      body: (rendered as Success<String>).value,
    );
  }

  String? _notifyDestination(PosAccount account) {
    final phone = account.notifyPhone?.trim();
    if (phone == null || phone.isEmpty) return null;
    if (PhoneNormalizer.isPhoneLike(phone)) {
      return PhoneNormalizer.forStorage(phone, asPhone: true);
    }
    return phone;
  }

  /// الإرسال عبر المحرّك المركزي: لا يوجد نص بديل عند غياب القالب.
  Future<Result<String>> _render(
    String key,
    Map<String, String> values,
  ) =>
      OutboundTemplateRenderer(settings: settings)
          .renderRegistered(key: key, values: values);
}
