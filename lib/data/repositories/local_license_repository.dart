part of local_repositories;

final class LocalLicenseRepository implements LicenseRepository {
  const LocalLicenseRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.License?>> getCurrent() async {
    try {
      final rows = await database.select(database.licenses).get();
      if (rows.isEmpty) return const Success(null);
      final row = rows.first;
      return Success(
        domain.License(
          id: row.id,
          status: domain.LicenseStatus.values.byName(row.status),
          activatedAt: row.activatedAt,
          expiresAt: row.expiresAt,
        ),
      );
    } catch (error) {
      return Failure(_failure('license_get_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.License license) async {
    try {
      await database.into(database.licenses).insertOnConflictUpdate(
            LicensesCompanion.insert(
              id: license.id,
              status: license.status.name,
              activatedAt: Value(license.activatedAt),
              expiresAt: Value(license.expiresAt),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('license_save_failed', error));
    }
  }
}
