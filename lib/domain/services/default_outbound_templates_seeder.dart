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

  /// Legacy bodies from released versions. We migrate only these exact system
  /// defaults; custom operator templates are never overwritten.
  static const _legacyPosCustomerTemplateWithoutCategory =
      'شبكة {NETWORK_NAME}\\n{cards}';
  static const _legacyPosCustomerTemplateWithValue =
      'شبكة {NETWORK_NAME}\\nالفئة: {CARD_VALUE} {CURRENCY}\\n{cards}';

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
      final value =
          existing is Success<AppSetting?> ? existing.value?.value.trim() : null;

      if (value != null && value.isNotEmpty) {
        final migrated = _migrateKnownLegacy(e.key, value);
        if (migrated != null && migrated != value) {
          final saved = await settings.save(
            AppSetting(key: e.key, value: migrated, updatedAt: clock.now()),
          );
          if (saved is Failure<void>) return Failure(saved.error);
        }
        continue;
      }

      final saved = await settings.save(
        AppSetting(key: e.key, value: e.value, updatedAt: clock.now()),
      );
      if (saved is Failure<void>) return Failure(saved.error);
    }

    final seeded = await settings.save(
      AppSetting(key: seededKey, value: 'true', updatedAt: clock.now()),
    );
    if (seeded is Failure<void>) return Failure(seeded.error);

    return const Success(null);
  }

  String? _migrateKnownLegacy(String key, String current) {
    if (key != SettingKeys.posCustomerCardDeliveryTemplate) return null;

    final normalized = current
        .replaceAll('\\r\\n', '\\n')
        .replaceAll(r'\\n', '\\n')
        .trim();
    final legacyWithoutCategory = _legacyPosCustomerTemplateWithoutCategory
        .replaceAll(r'\\n', '\\n');
    final legacyWithValue = _legacyPosCustomerTemplateWithValue
        .replaceAll(r'\\n', '\\n');
    if (normalized == legacyWithoutCategory ||
        normalized == legacyWithValue) {
      return SettingDefaults.posCustomerCardDeliveryTemplate;
    }
    return null;
  }
}
