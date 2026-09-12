part of local_repositories;

final class LocalWalletRepository implements WalletRepository {
  const LocalWalletRepository(this.database);

  final AppDatabase database;

  @override
  Future<Result<domain.Wallet?>> findById(String id) async {
    try {
      final row = await (database.select(database.wallets)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      return Success(row == null ? null : _toWallet(row));
    } catch (error) {
      return Failure(_failure('wallet_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Wallet>>> listAll() async {
    try {
      final rows = await (database.select(database.wallets)
            ..orderBy([(table) => OrderingTerm(expression: table.name)]))
          .get();
      return Success(rows.map(_toWallet).toList(growable: false));
    } catch (error) {
      return Failure(_failure('wallet_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.Wallet wallet) async {
    try {
      await database.into(database.wallets).insertOnConflictUpdate(
            WalletsCompanion.insert(
              id: wallet.id,
              name: wallet.name,
              status: wallet.status.name,
              createdAt: wallet.createdAt,
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('wallet_save_failed', error));
    }
  }

  domain.Wallet _toWallet(Wallet row) {
    return domain.Wallet(
      id: row.id,
      name: row.name,
      status: domain.WalletStatus.values.byName(row.status),
      createdAt: row.createdAt,
    );
  }
}
