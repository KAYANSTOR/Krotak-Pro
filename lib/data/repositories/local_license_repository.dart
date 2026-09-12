part of local_repositories;

final class LocalLicenseRepository implements LicenseRepository {
  const LocalLicenseRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.License?>> getCurrent() async {
    try {
      final rows = await database.select(database.licenses).get();
      if (rows.isEmpty) return const Success(null);
      return Success(_toLicense(rows.first));
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
      return const Success(null);
    } catch (error) {
      return Failure(_failure('license_save_failed', error));
    }
  }

  domain.License _toLicense(License row) {
    return domain.License(
      id: row.id,
      status: domain.LicenseStatus.values.byName(row.status),
      expiresAt: row.expiresAt,
      deviceBinding: row.deviceBinding,
    );
  }
}
