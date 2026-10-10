part of local_repositories;

/// WP-S4 / WP-5 — تنفيذ مستودع سجل عمليات استيراد الكروت.
///
/// الجدول `card_import_logs` منشأ بـSQL مباشر في `AppDatabase`
/// (انظر `_createCardImportLogsTable`) لأن ملف Drift المولّد يحتاج
/// إعادة توليد بـbuild_runner، لذا يُقرأ ويُكتب هنا بـSQL صريح.
/// الطوابع الزمنية بثواني Unix UTC (ترميز Drift الافتراضي).
final class LocalCardImportLogRepository implements CardImportLogRepository {
  const LocalCardImportLogRepository(this.database);

  final AppDatabase database;

  static const String _columns =
      'id, file_name, file_kind, status, total_rows, accepted_count, '
      'duplicate_count, rejected_count, category_id, category_name, '
      'failure_reason, rejected_details, started_at, finished_at';

  @override
  Future<Result<void>> save(domain.CardImportLog log) async {
    try {
      await database.customInsert(
        'INSERT OR REPLACE INTO card_import_logs ($_columns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(log.id),
          Variable<String>(log.fileName),
          Variable<String>(log.fileKind),
          Variable<String>(log.status.code),
          Variable<int>(log.totalRows),
          Variable<int>(log.acceptedCount),
          Variable<int>(log.duplicateCount),
          Variable<int>(log.rejectedCount),
          Variable<String>(log.categoryId),
          Variable<String>(log.categoryName),
          Variable<String>(log.failureReason),
          Variable<String>(_encodeRejections(log.rejections)),
          Variable<int>(_toSeconds(log.startedAt)),
          Variable<int>(log.finishedAt == null ? null : _toSeconds(log.finishedAt!)),
        ],
      );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_import_log_save_failed', error));
    }
  }

  @override
  Future<Result<domain.CardImportLog?>> findById(String id) async {
    try {
      final rows = await database
          .customSelect(
            'SELECT $_columns FROM card_import_logs WHERE id = ? LIMIT 1',
            variables: [Variable<String>(id)],
          )
          .get();
      if (rows.isEmpty) return const Success(null);
      return Success(_toLog(rows.first));
    } catch (error) {
      return Failure(_failure('card_import_log_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.CardImportLog>>> listRecent({int limit = 200}) async {
    try {
      final rows = await database
          .customSelect(
            'SELECT $_columns FROM card_import_logs '
            'ORDER BY started_at DESC, id DESC LIMIT ?',
            variables: [Variable<int>(limit <= 0 ? 200 : limit)],
          )
          .get();
      return Success(rows.map(_toLog).toList(growable: false));
    } catch (error) {
      return Failure(_failure('card_import_log_list_failed', error));
    }
  }

  @override
  Future<Result<void>> deleteLog(String id) async {
    try {
      await database.customUpdate(
        'DELETE FROM card_import_logs WHERE id = ?',
        variables: [Variable<String>(id)],
      );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('card_import_log_delete_failed', error));
    }
  }

  @override
  Future<Result<int>> count() async {
    try {
      final rows = await database
          .customSelect('SELECT COUNT(*) AS total FROM card_import_logs')
          .getSingle();
      return Success(rows.read<int>('total'));
    } catch (error) {
      return Failure(_failure('card_import_log_count_failed', error));
    }
  }

  domain.CardImportLog _toLog(QueryRow row) {
    final finished = row.readNullable<int>('finished_at');
    return domain.CardImportLog(
      id: row.read<String>('id'),
      fileName: row.read<String>('file_name'),
      fileKind: row.read<String>('file_kind'),
      status: domain.CardImportLogStatus.fromCode(row.read<String>('status')),
      totalRows: row.read<int>('total_rows'),
      acceptedCount: row.read<int>('accepted_count'),
      duplicateCount: row.read<int>('duplicate_count'),
      rejectedCount: row.read<int>('rejected_count'),
      categoryId: row.readNullable<String>('category_id'),
      categoryName: row.readNullable<String>('category_name'),
      failureReason: row.readNullable<String>('failure_reason'),
      rejections: _decodeRejections(row.readNullable<String>('rejected_details')),
      startedAt: _fromSeconds(row.read<int>('started_at')),
      finishedAt: finished == null ? null : _fromSeconds(finished),
    );
  }

  static int _toSeconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromSeconds(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();

  static String? _encodeRejections(List<domain.CardImportRejection> rejections) {
    if (rejections.isEmpty) return null;
    return jsonEncode(
      rejections.map((item) => item.toJson()).toList(growable: false),
    );
  }

  static List<domain.CardImportRejection> _decodeRejections(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <domain.CardImportRejection>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <domain.CardImportRejection>[];
      return decoded
          .whereType<Map>()
          .map((item) => domain.CardImportRejection.fromJson(
                item.map((key, value) => MapEntry('$key', value)),
              ))
          .toList(growable: false);
    } catch (_) {
      return const <domain.CardImportRejection>[];
    }
  }
}
