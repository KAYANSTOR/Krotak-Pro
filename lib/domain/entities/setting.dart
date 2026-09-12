abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
  static const preferredSimSlot = 'preferred_sim_slot';
  static const smsListenEnabled = 'sms_listen_enabled';
  static const batteryOptimizationAcknowledged = 'battery_optimization_acknowledged';
  static const lastExportAt = 'last_export_at';

  /// Display name of the network / point shown on Dashboard Header.
  /// Editable from Settings → اسم الشبكة. Empty/missing → [SettingDefaults.networkName].
  static const networkName = 'network_name';

  /// PD-07: automatic commercial processing (independent of [smsListenEnabled]).
  static const smsAutoProcessingEnabled = 'sms_auto_processing_enabled';

  /// PD-07: only process amounts that match an active card category face value.
  static const processCategoryAmountsOnly = 'process_category_amounts_only';

  /// PD-07: recover and process messages received while app/device was stopped.
  static const processOldMessagesOnResume = 'process_old_messages_on_resume';

  /// PD-07: POS balance-request handling (details deferred).
  static const posBalanceRequestsEnabled = 'pos_balance_requests_enabled';

  /// PD-07: auto daily operations summary (details deferred).
  static const dailyOpsSummaryAutoSend = 'daily_ops_summary_auto_send';

  /// PD-07: `light` | `dark` — mutually exclusive; default light.
  static const themeMode = 'theme_mode';
}

/// Defaults when a setting is unset (PD-07 Q1).
abstract final class SettingDefaults {
  static const networkName = 'NET';
  static const smsAutoProcessingEnabled = true;
  static const processCategoryAmountsOnly = true;
  static const processOldMessagesOnResume = true;
  static const posBalanceRequestsEnabled = true;
  static const dailyOpsSummaryAutoSend = true;

  /// Stored value for [SettingKeys.themeMode].
  static const themeMode = 'light';
}

final class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;
}
