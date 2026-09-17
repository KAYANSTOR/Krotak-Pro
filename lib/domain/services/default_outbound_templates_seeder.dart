import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'local_advance_service.dart';

/// Seeds default *outbound* SMS bodies used by product features (سلفني, عروض).
/// Operators can edit them later from Settings screens.
final class DefaultOutboundTemplatesSeeder {
  const DefaultOutboundTemplatesSeeder({
    required this.settings,
    required this.clock,
  });

  final SettingsRepository settings;
  final Clock clock;

  static const seededKey = 'default_outbound_templates_seeded_v1';

  Future<Result<void>> seedIfNeeded() async {
    final flag = await settings.find(seededKey);
    if (flag is Success<AppSetting?> && flag.value?.value == 'true') {
      return const Success(null);
    }

    final defaults = <String, String>{
      SettingKeys.salafniAcceptedTemplate: LocalAdvanceService.defaultAccepted,
      SettingKeys.salafniRejectedTemplate: LocalAdvanceService.defaultRejected,
      SettingKeys.salafniSettledTemplate: LocalAdvanceService.defaultSettled,
      SettingKeys.promotionRewardSmsTemplate:
          SettingDefaults.promotionRewardSmsTemplate,
    };

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
