enum LicenseStatus {
  unknown,
  active,
  trial,
  expired,
  invalid,
  offlineGrace,
}

final class License {
  const License({
    required this.id,
    required this.status,
    required this.expiresAt,
    this.deviceBinding,
    this.token,
  });

  final String id;
  final LicenseStatus status;
  final DateTime? expiresAt;
  final String? deviceBinding;
  /// رمز Ed25519 الموقّع. لا يُضمّن في النسخ الاحتياطية العامة.
  final String? token;
}
