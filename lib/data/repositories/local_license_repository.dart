part of local_repositories;

final class LocalLicenseRepository implements LicenseRepository {
  const LocalLicenseRepository(this.database, {this.settings});

  final AppDatabase database;
  final SettingsRepository? settings;

  @override
  Future<Result<domain.License?>> getCurrent() async {
    try {
      final rows = await database.select(database.licenses).get();
      if (rows.isEmpty) return const Success(null);
      String? token;
      final settingsRepo = settings;
      if (settingsRepo != null) {
        final stored = await settingsRepo.find(domain.SettingKeys.licenseToken);
        if (stored is Success<domain.AppSetting?>) {
          token = stored.value?.value;
        }
      }
      return Success(_toLicense(rows.first, token: token));
    } catch (error) {
      return Failure(_failure('license_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.License license) async {
    try {
      await database.into(database.licenses).insertOnConflictUpdate(
            LicensesCompanion.insert(
              id: license.id,
              status: license.status.name,
              expiresAt: Value(license.expiresAt),
              deviceBinding: Value(license.deviceBinding),
            ),
          );
      final token = license.token;
      final settingsRepo = settings;
      if (token != null && token.isNotEmpty && settingsRepo != null) {
        final tokenSave = await settingsRepo.save(domain.AppSetting(
          key: domain.SettingKeys.licenseToken,
          value: token,
          updatedAt: DateTime.now(),
        ));
        if (tokenSave is Failure<void>) return Failure(tokenSave.error);
      }
      return const Success(null);
    } catch (error) {
      return Failure(_failure('license_save_failed', error));
    }
  }

  domain.License _toLicense(License row, {String? token}) {
    return domain.License(
      id: row.id,
      status: domain.LicenseStatus.values.byName(row.status),
      expiresAt: row.expiresAt,
      deviceBinding: row.deviceBinding,
      token: token,
    );
  }
}
