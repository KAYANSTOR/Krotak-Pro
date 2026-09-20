/// Device phone-book lookup for customer identity decisions.
///
/// When a deposit arrives from an unknown phone:
/// - found in contacts => full [CustomerStatus.active] with contact display name
/// - not found / no permission => [CustomerStatus.provisional] ledger-only
abstract interface class ContactDirectory {
  /// Returns a match when [phone] exists in device contacts with a display name.
  Future<DeviceContactMatch?> findByPhone(String phone);
}

final class DeviceContactMatch {
  const DeviceContactMatch({
    required this.displayName,
    required this.phone,
  });

  final String displayName;
  final String phone;
}
