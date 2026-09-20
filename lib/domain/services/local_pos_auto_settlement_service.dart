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
      return Failure<Transaction>(credited.error);
    }
    final tx = (credited as Success<Transaction>).value;

    final remaining = await _remainingDebt(
      customerId: account.customerId,
      currencyCode: transfer.amount.currencyCode,
    );

    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'pos_settlement',
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
    final setting = await settings.find(SettingKeys.posAutoSettlementEnabled);
    if (setting is Failure<AppSetting?>) return true;
    return SettingBool.read(
      (setting as Success<AppSetting?>).value?.value,
      defaultValue: SettingDefaults.posAutoSettlementEnabled,
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
    final byId = await posRegistry.findByIdentifier(identifier);
    if (byId is Failure<PosAccount?>) return byId;
    final hit = (byId as Success<PosAccount?>).value;
    if (hit != null && transfer.posId != null && transfer.posId!.isNotEmpty) {
      if (hit.posId != transfer.posId) {
        return const Success(null);
      }
    }
    return Success(hit);
  }

  Future<int> _remainingDebt({
    required String customerId,
    required String currencyCode,
  }) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is! Success<List<Transaction>>) return 0;
    try {
      final balance = sumCompletedLedger(
        transactions: rows.value,
        currencyCode: currencyCode,
      );
      return balance.minorUnits < 0 ? -balance.minorUnits : 0;
    } on Object {
      return 0;
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
    final raw = await _template(
      SettingKeys.posSettlementSuccessTemplate,
      SettingDefaults.posSettlementSuccessTemplate,
    );
    final amountText = (amount.minorUnits / 100).toStringAsFixed(0);
    final remainingText = (remainingDebt / 100).toStringAsFixed(0);
    final body = raw
        .replaceAll('{pos}', account.name)
        .replaceAll('{amount}', amountText)
        .replaceAll('{SETTLEMENT_AMOUNT}', amountText)
        .replaceAll('{remaining}', remainingText)
        .replaceAll('{REMAINING_BALANCE}', remainingText)
        .replaceAll('{identifier}', account.identifiers.isEmpty ? '' : account.identifiers.first);
    await sender.send(destination: dest, body: body);
  }

  Future<void> _notifyFailure(PosAccount account, {required String reason}) async {
    final dest = _notifyDestination(account);
    final sender = messageSender;
    if (dest == null || sender == null) return;
    final raw = await _template(
      SettingKeys.posSettlementFailedTemplate,
      SettingDefaults.posSettlementFailedTemplate,
    );
    final body = raw
        .replaceAll('{pos}', account.name)
        .replaceAll('{reason}', reason);
    await sender.send(destination: dest, body: body);
  }

  String? _notifyDestination(PosAccount account) {
    final phone = account.notifyPhone?.trim();
    if (phone == null || phone.isEmpty) return null;
    if (PhoneNormalizer.isPhoneLike(phone)) {
      return PhoneNormalizer.forStorage(phone, asPhone: true);
    }
    return phone;
  }

  Future<String> _template(String key, String fallback) async {
    final found = await settings.find(key);
    if (found is Success<AppSetting?>) {
      final value = found.value?.value.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }
}
