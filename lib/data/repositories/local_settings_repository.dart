part of local_repositories;

final class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.AppSetting?>> find(String key) async {
    try {
      final row = await (database.select(database.appSettings)
            ..where((table) => table.key.equals(key)))
          .getSingleOrNull();
      return Success(row == null ? null : _toSetting(row));
    } catch (error) {
      return Failure(_failure('setting_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.AppSetting setting) async {
    try {
      await database.into(database.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: setting.key,
              value: setting.value,
              updatedAt: setting.updatedAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('setting_save_failed', error));
    }
  }

  domain.AppSetting _toSetting(AppSetting row) {
    return domain.AppSetting(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }
}
