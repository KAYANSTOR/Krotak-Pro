import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'local_advance_service.dart';

/// Seeds default *outbound* SMS bodies used across the product:
/// العملاء · العروض · النظام / نقاط البيع · سلفني.
///
/// Bodies follow the product video catalog and [docs/screenshot-spec-appendix.md].
/// Operators can edit any template later from Settings → قوالب الرسائل.
final class DefaultOutboundTemplatesSeeder {
  const DefaultOutboundTemplatesSeeder({
    required this.settings,
    required this.clock,
  });

  final SettingsRepository settings;
  final Clock clock;

  /// Bump when new catalog keys are added so existing installs backfill.
  static const seededKey = 'default_outbound_templates_seeded_v4';

  /// Full catalog keyed by [SettingKeys] → default body.
  static Map<String, String> catalog() => <String, String>{
        SettingKeys.voucherDeliverySmsTemplate:
            SettingDefaults.voucherDeliverySmsTemplate,
        SettingKeys.posCustomerCardDeliveryTemplate:
            SettingDefaults.posCustomerCardDeliveryTemplate,
        SettingKeys.posOrderSuccessTemplate:
            SettingDefaults.posOrderSuccessTemplate,
        SettingKeys.customerDebtPaymentTemplate:
            SettingDefaults.customerDebtPaymentTemplate,
        SettingKeys.promotionRewardSmsTemplate:
            SettingDefaults.promotionRewardSmsTemplate,
        SettingKeys.salafniAcceptedTemplate: LocalAdvanceService.defaultAccepted,
        SettingKeys.salafniRejectedTemplate: LocalAdvanceService.defaultRejected,
        SettingKeys.salafniSettledTemplate: LocalAdvanceService.defaultSettled,
        SettingKeys.posBalanceResponseTemplate:
            SettingDefaults.posBalanceResponseTemplate,
        SettingKeys.posCreditLimitExceededTemplate:
            SettingDefaults.posCreditLimitExceededTemplate,
        SettingKeys.dailyPosSummaryTemplate:
            SettingDefaults.dailyPosSummaryTemplate,
        SettingKeys.posSettlementSuccessTemplate:
            SettingDefaults.posSettlementSuccessTemplate,
        SettingKeys.posSettlementFailedTemplate:
            SettingDefaults.posSettlementFailedTemplate,
        SettingKeys.posSettlementUnknownTemplate:
            SettingDefaults.posSettlementUnknownTemplate,
        SettingKeys.posRequestRejectedTemplate:
            SettingDefaults.posRequestRejectedTemplate,
        SettingKeys.posCustomerSmsTailTemplate:
            SettingDefaults.posCustomerSmsTailTemplate,
        SettingKeys.lowStockAlertTemplate:
            SettingDefaults.lowStockAlertTemplate,
        SettingKeys.posInstantChargeConfirmTemplate:
            SettingDefaults.posInstantChargeConfirmTemplate,
      };

  Future<Result<void>> seedIfNeeded() async {
    final defaults = catalog();
    for (final e in defaults.entries) {
      final existing = await settings.find(e.key);
      final has = existing is Success<AppSetting?> &&
          (existing.value?.value.trim().isNotEmpty ?? false);
      if (has) continue;
      await settings.save(
        AppSetting(key: e.key, value: e.value, updatedAt: clock.now()),
      );
    }

    await settings.save(
      AppSetting(key: seededKey, value: 'true', updatedAt: clock.now()),
    );
    return const Success(null);
  }
}
