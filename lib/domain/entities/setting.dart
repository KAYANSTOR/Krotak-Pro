abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
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
