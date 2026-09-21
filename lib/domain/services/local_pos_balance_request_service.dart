import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'local_pos_account_registry.dart';
import 'services.dart';

final class LocalPosBalanceRequestService {
  const LocalPosBalanceRequestService({
    required this.posRegistry,
    required this.balances,
    required this.settings,
    required this.auditLogs,
    required this.messageSender,
    required this.clock,
    required this.ids,
  });

  final LocalPosAccountRegistry posRegistry;
  final CustomerBalanceService balances;
  final SettingsRepository settings;
  final AuditLogRepository auditLogs;
  final MessageSender messageSender;
  final Clock clock;
  final IdGenerator ids;

  static const int defaultDailyLimit = 5;

  Future<Result<void>> handle({
    required IncomingMessage message,
    required ParsedTransfer parsed,
  }) async {
    final enabled = await settings.find(SettingKeys.posBalanceRequestsEnabled);
    if (enabled is Success<AppSetting?> &&
        !SettingBool.read(
          enabled.value?.value,
          defaultValue: SettingDefaults.posBalanceRequestsEnabled,
        )) {
      return const Failure(
        AppFailure(code: 'pos_balance_requests_disabled', message: 'طلبات رصيد نقاط البيع معطلة'),
      );
    }

    final accountResult = await posRegistry.findByIdentifier(message.sender);
    if (accountResult is Failure) return Failure((accountResult as Failure).error);
    final account = (accountResult as Success).value;
    if (account == null || account.status.name != 'active') {
      return const Failure(
        AppFailure(code: 'pos_not_found', message: 'نقطة البيع غير موجودة أو غير نشطة'),
      );
    }

    final limitSetting = await settings.find(SettingKeys.posBalanceDailyLimit);
    final dailyLimit = limitSetting is Success<AppSetting?>
        ? SettingInt.read(
            limitSetting.value?.value,
            defaultValue: SettingDefaults.posBalanceDailyLimit,
          )
        : SettingDefaults.posBalanceDailyLimit;
    final effectiveLimit = dailyLimit < 0 ? 0 : dailyLimit;

    final logs = await auditLogs.findByEntity('pos_balance_request', account.posId);
    if (logs is Failure) return Failure((logs as Failure).error);
    final today = clock.now();
    final used = (logs as Success<List<AuditLog>>).value.where((e) {
      final d = e.occurredAt;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).length;
    if (used >= effectiveLimit) {
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'pos_balance_request',
          entityId: account.posId,
          action: 'daily_limit_exceeded',
          occurredAt: clock.now(),
          payloadJson: '{"used":"$used","limit":"$effectiveLimit"}',
        ),
      );
      return const Failure(
        AppFailure(code: 'pos_balance_daily_limit', message: 'تم تجاوز الحد اليومي لطلبات الرصيد'),
      );
    }

    final balanceResult = await balances.getBalance(
      customerId: account.customerId,
      currencyCode: 'YER',
    );
    if (balanceResult is Failure) return Failure((balanceResult as Failure).error);
    final balance = (balanceResult as Success).value;
    final balanceText = (balance.minorUnits / 100).toStringAsFixed(2);
    final debtMinor = balance.minorUnits < 0 ? -balance.minorUnits : 0;
    final debtText = (debtMinor / 100).toStringAsFixed(2);

    final setting = await settings.find(SettingKeys.posBalanceResponseTemplate);
    final template = setting is Success<AppSetting?> && setting.value != null
        ? setting.value!.value
        : SettingDefaults.posBalanceResponseTemplate;
    final body = template
        .replaceAll('{pos}', account.name)
        .replaceAll('{balance}', balanceText)
        .replaceAll('{debt}', debtText);

    final destination = account.notifyPhone ?? message.sender;
    final sent = await messageSender.send(destination: destination, body: body);
    if (sent is Failure<void>) return sent;

    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'pos_balance_request',
        entityId: account.posId,
        action: 'responded',
        occurredAt: clock.now(),
        payloadJson: '{"messageId":"balance-request","balance":"$balanceText","debt":"$debtText"}',
      ),
    );
    return const Success(null);
  }
}
