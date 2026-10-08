import '../entities/license.dart';
import '../repositories/repositories.dart';
import '../../core/clock.dart';
import '../../core/result.dart';
import 'license_token_codec.dart';
import 'services.dart';

/// يتحقق محليًا من رمز الترخيص الموقّع بالمفتاح العام المضمّن.
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
    final stored = (result as Success<License?>).value;
    if (stored == null) {
      return const Failure(AppFailure(
        code: 'license_missing',
        message: 'لا يوجد رمز ترخيص مثبت على هذا الجهاز.',
      ));
    }
    final token = stored.token;
    if (token == null || token.trim().isEmpty) {
      return const Failure(AppFailure(
        code: 'license_token_missing',
        message: 'الترخيص القديم غير موقع. أدخل رمز ترخيص جديد.',
      ));
    }
    final verified = await LicenseTokenCodec.verify(token);
    if (verified is Failure<LicenseTokenData>) return Failure(verified.error);
    final data = (verified as Success<LicenseTokenData>).value;
    if (data.id != stored.id) {
      return const Failure(AppFailure(
        code: 'license_id_mismatch',
        message: 'رمز الترخيص لا يطابق السجل المحلي.',
      ));
    }
    return Success(_evaluate(License(
      id: data.id,
      status: LicenseStatus.active,
      expiresAt: data.expiresAt,
      deviceBinding: data.deviceBinding,
      token: data.token,
    )));
  }

  /// يثبت رمزًا أصدرته أداة الإدارة فقط. لا توجد حالة تفعيل دائم محلية.
  Future<Result<License>> activateToken(String rawToken) async {
    final verified = await LicenseTokenCodec.verify(rawToken);
    if (verified is Failure<LicenseTokenData>) return Failure(verified.error);
    final data = (verified as Success<LicenseTokenData>).value;
    final now = clock.now();
    if (data.issuedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return const Failure(AppFailure(
        code: 'license_not_yet_valid',
        message: 'رمز الترخيص صادر بتاريخ مستقبلي.',
      ));
    }
    if (data.expiresAt != null && !now.isBefore(data.expiresAt!)) {
      return const Failure(AppFailure(
        code: 'license_expired',
        message: 'رمز الترخيص منتهي الصلاحية.',
      ));
    }
    final license = License(
      id: data.id,
      status: LicenseStatus.active,
      expiresAt: data.expiresAt,
      deviceBinding: data.deviceBinding,
      token: data.token,
    );
    final save = await licenses.save(license);
    if (save is Failure<void>) return Failure(save.error);
    return Success(_evaluate(license));
  }

  @override
  Future<Result<void>> verifyOnline() async {
    final currentResult = await current();
    if (currentResult is Failure<License>) return Failure(currentResult.error);
    final license = (currentResult as Success<License>).value;
    if (license.status == LicenseStatus.expired ||
        license.status == LicenseStatus.invalid) {
      return Failure(AppFailure(
        code: 'license_${license.status.name}',
        message: 'انتهت صلاحية الترخيص أو أصبح غير صالح.',
      ));
    }
    return const Success(null);
  }

  License _evaluate(License license) {
    final expires = license.expiresAt;
    if (expires == null) return license;
    final now = clock.now();
    if (now.isBefore(expires)) {
      return License(
        id: license.id,
        status: LicenseStatus.active,
        expiresAt: expires,
        deviceBinding: license.deviceBinding,
        token: license.token,
      );
    }
    final graceEnd = expires.add(gracePeriod);
    if (now.isBefore(graceEnd)) {
      return License(
        id: license.id,
        status: LicenseStatus.offlineGrace,
        expiresAt: expires,
        deviceBinding: license.deviceBinding,
        token: license.token,
      );
    }
    return License(
      id: license.id,
      status: LicenseStatus.expired,
      expiresAt: expires,
      deviceBinding: license.deviceBinding,
      token: license.token,
    );
  }
}
