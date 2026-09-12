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
      if (row == null) return const Success(null);
      return Success(
        domain.AppSetting(key: row.key, value: row.value),
      );
    } catch (error) {
      return Failure(_failure('settings_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.AppSetting setting) async {
    try {
      await database.into(database.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: setting.key,
              value: setting.value,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('settings_save_failed', error));
    }
  }
}
