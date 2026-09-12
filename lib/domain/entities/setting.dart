abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
  static const preferredSimSlot = 'preferred_sim_slot';
  static const smsListenEnabled = 'sms_listen_enabled';
  static const batteryOptimizationAcknowledged = 'battery_optimization_acknowledged';
  static const lastExportAt = 'last_export_at';

  /// Display name of the network / point shown on Dashboard Header.
  /// Editable from Settings → اسم الشبكة. Empty/missing → [defaultNetworkName].
  static const networkName = 'network_name';
}

/// Default Dashboard / app display name when [SettingKeys.networkName] is unset.
abstract final class SettingDefaults {
  static const networkName = 'NET';
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
