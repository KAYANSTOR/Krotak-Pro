import '../../core/result.dart';

/// Device phone-book lookup for customer identity decisions.
abstract interface class ContactDirectory {
  /// Returns a match when [phone] exists in device contacts with a display name.
  Future<DeviceContactMatch?> findByPhone(String phone);
}

/// Writes a depositor to the device phone book without making the phone book
/// part of the ledger identity.
abstract interface class ContactWriter {
  Future<Result<void>> upsertPhone({
    required String phone,
    required String displayName,
  });
}

final class DeviceContactMatch {
  const DeviceContactMatch({
    required this.displayName,
    required this.phone,
  });

  final String displayName;
  final String phone;
}
