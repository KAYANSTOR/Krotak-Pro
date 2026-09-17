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
      if (row == null) return const Success(null);
      final extras = await _readExtras();
      return Success(_toWallet(row, extras[id]));
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
      final extras = await _readExtras();
      return Success(
        rows
            .map((row) => _toWallet(row, extras[row.id]))
            .toList(growable: false),
      );
    } catch (error) {
      return Failure(_failure('wallet_list_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.Wallet wallet) async {
    try {
      await database.transaction(() async {
        await database.into(database.wallets).insertOnConflictUpdate(
              WalletsCompanion.insert(
                id: wallet.id,
                name: wallet.name,
                status: wallet.status.name,
                createdAt: wallet.createdAt,
              ),
            );

        final extras = await _readExtras();
        extras[wallet.id] = <String, dynamic>{
          'senderId': wallet.senderId,
          'sourceMode': wallet.sourceMode.name,
          'packageName': wallet.packageName,
        };
        await database.into(database.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: domain.SettingKeys.walletExtras,
                value: jsonEncode(extras),
                updatedAt: wallet.createdAt,
              ),
            );
      });
      return const Success(null);
    } catch (error) {
      return Failure(_failure('wallet_save_failed', error));
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readExtras() async {
    final row = await (database.select(database.appSettings)
          ..where((table) => table.key.equals(domain.SettingKeys.walletExtras)))
        .getSingleOrNull();
    if (row == null || row.value.trim().isEmpty) {
      return <String, Map<String, dynamic>>{};
    }
    try {
      final decoded = jsonDecode(row.value);
      if (decoded is! Map) return <String, Map<String, dynamic>>{};
      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        result[entry.key as String] =
            Map<String, dynamic>.from(entry.value as Map);
      }
      return result;
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  domain.Wallet _toWallet(
    Wallet row,
    Map<String, dynamic>? extra,
  ) {
    final sourceModeRaw = extra?['sourceMode']?.toString();
    final sourceMode = domain.WalletSourceMode.values.firstWhere(
      (mode) => mode.name == sourceModeRaw,
      orElse: () => domain.WalletSourceMode.sms,
    );
    return domain.Wallet(
      id: row.id,
      name: row.name,
      status: domain.WalletStatus.values.byName(row.status),
      createdAt: row.createdAt,
      senderId: extra?['senderId']?.toString(),
      sourceMode: sourceMode,
      packageName: extra?['packageName']?.toString(),
    );
  }
}
