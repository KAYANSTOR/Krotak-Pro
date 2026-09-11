import '../entities/license.dart';
import '../repositories/repositories.dart';
import '../../core/clock.dart';
import '../../core/result.dart';
import 'services.dart';

/// Local-first license checks. Online verification is a no-op until backend exists.
final class LocalLicenseService implements LicenseService {
  const LocalLicenseService({
    required this.licenses,
    required this.clock,
    this.gracePeriod = const Duration(days: 7),
  });

  final LicenseRepository licenses;
  final Clock clock;
  final Duration gracePeriod;

  Future<Result<License>> current() async {
    final result = await licenses.getCurrent();
    if (result is Failure<License?>) return Failure(result.error);
    final license = (result as Success<License?>).value;
    if (license == null) {
      return const Failure(
        AppFailure(code: 'license_missing', message: 'No license installed'),
      );
    }
    return Success(_evaluate(license));
  }

  Future<Result<License>> activateOffline({
    required String licenseId,
    required DateTime expiresAt,
    String? deviceBinding,
  }) async {
    final license = License(
      id: licenseId,
      status: LicenseStatus.active,
      expiresAt: expiresAt,
      deviceBinding: deviceBinding,
    );
    final save = await licenses.save(license);
    if (save is Failure<void>) return Failure(save.error);
    return Success(_evaluate(license));
  }

  @override
  Future<Result<void>> verifyOnline() async {
    // Offline-first product: online check is optional and currently a stub.
    final currentResult = await current();
    if (currentResult is Failure<License>) return Failure(currentResult.error);
    final license = (currentResult as Success<License>).value;
    if (license.status == LicenseStatus.expired ||
        license.status == LicenseStatus.invalid) {
      return Failure(
        AppFailure(
          code: 'license_${license.status.name}',
          message: 'License is ${license.status.name}',
        ),
      );
    }
    return const Success(null);
  }

  License _evaluate(License license) {
    final now = clock.now();
    final expires = license.expiresAt;
    if (expires == null) return license;

    if (now.isBefore(expires)) {
      return License(
        id: license.id,
        status: LicenseStatus.active,
        expiresAt: expires,
        deviceBinding: license.deviceBinding,
      );
    }

    final graceEnd = expires.add(gracePeriod);
    if (now.isBefore(graceEnd)) {
      return License(
        id: license.id,
        status: LicenseStatus.offlineGrace,
        expiresAt: expires,
        deviceBinding: license.deviceBinding,
      );
    }

    return License(
      id: license.id,
      status: LicenseStatus.expired,
      expiresAt: expires,
      deviceBinding: license.deviceBinding,
    );
  }
}
