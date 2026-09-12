part of local_repositories;

final class LocalCardCategoryRepository implements CardCategoryRepository {
  const LocalCardCategoryRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.CardCategory?>> findById(String id) async {
    try {
      final row = await (database.select(database.cardCategories)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toCategory(row));
    } catch (error) {
      return Failure(_failure('category_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.CardCategory>>> listAll() async {
    try {
      final rows = await (database.select(database.cardCategories)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toCategory).toList(growable: false));
    } catch (error) {
      return Failure(_failure('category_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.CardCategory category) async {
    try {
      await database.into(database.cardCategories).insertOnConflictUpdate(
            CardCategoriesCompanion.insert(
              id: category.id,
              name: category.name,
              faceValueMinorUnits: category.faceValue.minorUnits,
              currencyCode: category.faceValue.currencyCode,
              isActive: Value(category.isActive),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('category_save_failed', error));
    }
  }

  domain.CardCategory _toCategory(CardCategory row) {
    return domain.CardCategory(
      id: row.id,
      name: row.name,
      faceValue: Money(
        minorUnits: row.faceValueMinorUnits,
        currencyCode: row.currencyCode,
      ),
      isActive: row.isActive,
    );
  }
}
