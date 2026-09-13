abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
  static const preferredSimSlot = 'preferred_sim_slot';
  static const smsListenEnabled = 'sms_listen_enabled';
  static const batteryOptimizationAcknowledged = 'battery_optimization_acknowledged';
  static const lastExportAt = 'last_export_at';
  static const networkName = 'network_name';
  static const smsAutoProcessingEnabled = 'sms_auto_processing_enabled';
  static const processCategoryAmountsOnly = 'process_category_amounts_only';
  static const processOldMessagesOnResume = 'process_old_messages_on_resume';
  static const posBalanceRequestsEnabled = 'pos_balance_requests_enabled';
  static const dailyOpsSummaryAutoSend = 'daily_ops_summary_auto_send';
  static const themeMode = 'theme_mode';
  static const lastRejectedMessagesViewedAt = 'last_rejected_messages_viewed_at';

  /// JSON list of configured notification payment sources.
  static const notificationSources = 'notification_sources';
}

abstract final class SettingDefaults {
  static const networkName = 'NET';
  static const smsAutoProcessingEnabled = true;
  static const processCategoryAmountsOnly = true;
  static const processOldMessagesOnResume = true;
  static const posBalanceRequestsEnabled = true;
  static const dailyOpsSummaryAutoSend = true;
  static const themeMode = 'light';
}

final class AppSetting {
  const AppSetting({required this.key, required this.value, required this.updatedAt});
  final String key;
  final String value;
  final DateTime updatedAt;
}

abstract final class SettingBool {
  static bool read(String? raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    final v = raw.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
    return defaultValue;
  }
}
