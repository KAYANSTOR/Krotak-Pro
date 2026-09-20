part of local_repositories;

final class LocalTransferTemplateRepository implements TransferTemplateRepository {
  const LocalTransferTemplateRepository(this.database);

  final AppDatabase database;

  static const _columns = 'id, name, pattern, is_active, '
      'wallet_id, priority, sample_body, sender_code, identifier_kind, '
      'pos_id, sender_name_label, note_label, require_reference';

  @override
  Future<Result<List<domain.TransferTemplate>>> listAll() async {
    try {
      final rows = await database.customSelect(
        'SELECT $_columns '
        'FROM transfer_templates ORDER BY priority ASC, name ASC',
        readsFrom: {database.transferTemplates},
      ).get();
      return Success(rows.map(_fromRow).toList(growable: false));
    } catch (error) {
      return Failure(_failure('template_list_failed', error));
    }
  }

  @override
  Future<Result<List<domain.TransferTemplate>>> listByWallet(String? walletId) async {
    try {
      final rows = walletId == null
          ? await database.customSelect(
              'SELECT $_columns '
              'FROM transfer_templates ORDER BY priority ASC, name ASC',
              readsFrom: {database.transferTemplates},
            ).get()
          : await database.customSelect(
              'SELECT $_columns '
              'FROM transfer_templates WHERE wallet_id = ? '
              'ORDER BY priority ASC, name ASC',
              variables: [Variable.withString(walletId)],
              readsFrom: {database.transferTemplates},
            ).get();
      return Success(rows.map(_fromRow).toList(growable: false));
    } catch (error) {
      return Failure(_failure('template_list_by_wallet_failed', error));
    }
  }

  @override
  Future<Result<domain.TransferTemplate?>> findById(String id) async {
    try {
      final rows = await database.customSelect(
        'SELECT $_columns '
        'FROM transfer_templates WHERE id = ? LIMIT 1',
        variables: [Variable.withString(id)],
        readsFrom: {database.transferTemplates},
      ).get();
      if (rows.isEmpty) return const Success(null);
      return Success(_fromRow(rows.first));
    } catch (error) {
      return Failure(_failure('template_find_failed', error));
    }
  }

  @override
  Future<Result<void>> save(domain.TransferTemplate template) async {
    try {
      await database.into(database.transferTemplates).insertOnConflictUpdate(
            TransferTemplatesCompanion.insert(
              id: template.id,
              name: template.name,
              pattern: template.pattern,
              isActive: Value(template.isActive),
            ),
          );
      await database.customStatement(
        'UPDATE transfer_templates SET '
        'wallet_id = ?, priority = ?, sample_body = ?, sender_code = ?, identifier_kind = ?, '
        'pos_id = ?, sender_name_label = ?, note_label = ?, require_reference = ? '
        'WHERE id = ?',
        [
          template.walletId,
          template.priority,
          template.sampleBody,
          template.senderCode,
          template.identifierKind.name,
          template.posId,
          template.senderNameLabel,
          template.noteLabel,
          template.requireReference ? 1 : 0,
          template.id,
        ],
      );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('template_save_failed', error));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await (database.delete(database.transferTemplates)
            ..where((t) => t.id.equals(id)))
          .go();
      return const Success(null);
    } catch (error) {
      return Failure(_failure('template_delete_failed', error));
    }
  }

  domain.TransferTemplate _fromRow(QueryRow row) {
    final kindRaw = row.read<String?>('identifier_kind') ?? 'phone';
    final kind = domain.TemplateIdentifierKind.values.firstWhere(
      (k) => k.name == kindRaw,
      orElse: () => domain.TemplateIdentifierKind.phone,
    );
    return domain.TransferTemplate(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      pattern: row.read<String>('pattern'),
      isActive: row.read<bool>('is_active'),
      walletId: row.read<String?>('wallet_id'),
      posId: row.read<String?>('pos_id'),
      priority: row.read<int?>('priority') ?? 0,
      sampleBody: row.read<String?>('sample_body'),
      senderCode: row.read<String?>('sender_code'),
      identifierKind: kind,
      senderNameLabel: row.read<String?>('sender_name_label'),
      noteLabel: row.read<String?>('note_label'),
      // Raw ALTER-ed column (not a declared BoolColumn) — read as int and
      // coerce manually rather than `read<bool>()`, and default to the
      // safe value (required) for any pre-existing row where it's null.
      requireReference: (row.read<int?>('require_reference') ?? 1) != 0,
    );
  }
}
