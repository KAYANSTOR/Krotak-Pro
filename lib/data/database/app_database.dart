import 'dart:convert';

import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get status => text()();
  TextColumn get mergedIntoId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerIdentifiers extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();
  TextColumn get value => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PointOfSales extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CardCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get faceValueMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  TextColumn get serialNumber => text()();
  TextColumn get secretCode => text()();
  TextColumn get status => text()();
  TextColumn get reservationId => text().nullable()();
  DateTimeColumn get reservedAt => dateTime().nullable()();
  DateTimeColumn get reservationExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get status => text()();
  IntColumn get amountMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get customerId => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get relatedTransactionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get cardId => text()();
  IntColumn get amountMinorUnits => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TransferTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get pattern => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class IncomingMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get externalReference => text().nullable()();
  TextColumn get customerIdentifier => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Licenses extends Table {
  TextColumn get id => text()();
  TextColumn get status => text()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get deviceBinding => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// مهام الرسائل الجماعية. مصدر الحقيقة الوحيد لها وقت التشغيل هو هذه الجداول،
/// و`app_settings['broadcast_jobs']` القديم يُقرأ مرة واحدة للترحيل فقط.
@DataClassName('BroadcastJobRow')
class BroadcastJobs extends Table {
  TextColumn get id => text()();
  TextColumn get body => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get fingerprint => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BroadcastRecipientRow')
class BroadcastRecipients extends Table {
  TextColumn get jobId => text()();
  TextColumn get customerId => text()();

  /// ترتيب المستلم داخل المهمة كما رتّبه التصنيف (1-based للعرض).
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get phone => text()();
  TextColumn get displayName => text()();
  TextColumn get status => text()();
  TextColumn get errorCode => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get sentAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {jobId, customerId};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Customers,
    CustomerIdentifiers,
    Wallets,
    PointOfSales,
    CardCategories,
    Cards,
    Transactions,
    Sales,
    TransferTemplates,
    IncomingMessages,
    Licenses,
    AppSettings,
    AuditLogs,
    BroadcastJobs,
    BroadcastRecipients,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 5 — جداول البث المسمّاة صارت مصدر الحقيقة الوحيد (بدل JSON الإعدادات).
  /// 6 — جدول سجل عمليات استيراد الكروت (card_import_logs) لإدارة ملفات الاستيراد (WP-S4/WP-5 — القرار D8). الترقية إضافية فقط ولا تمس أي بيانات.
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async {
          await migrator.createAll();
          await _ensureTransferTemplateColumns();
          await _createIdempotencyIndexes();
          await _createPerformanceIndexes();
          await _createBroadcastTables();
          await _createCardImportLogsTable();
          await _ensureBroadcastColumns();
          await _applySqlitePragmas();
        },
        onUpgrade: (Migrator migrator, int from, int to) async {
          // Never wipe data. All steps are additive / IF NOT EXISTS / best-effort.
          // الأعمدة المُضافة تُعاد أولًا وبلا شرط: فهارس الأداء التالية تلمسها،
          // وملف قديم ناقص عمودًا يجب أن يترقّى بدل أن يفشل فتحه.
          await _ensureTransferTemplateColumns();
          if (from < 2) {
            await _ensureTransferTemplateColumns();
          }
          if (from < 3) {
            await _createIdempotencyIndexes();
          }
          if (from < 4) {
            // Fix unique index on secret_code that broke upgrades when multiple
            // serial-only cards share empty secret ('').
            await customStatement(
              'DROP INDEX IF EXISTS idx_cards_secret_code',
            );
            await _createIdempotencyIndexes();
            await _ensureTransferTemplateColumns();
          }
          await _createPerformanceIndexes();
          await _createBroadcastTables();
          await _createCardImportLogsTable();
          await _ensureBroadcastColumns();
          if (from < 5) {
            // ترحيل JSON الإعدادات إلى الجداول المسمّاة — إضافي فقط، ولا يكتب
            // فوق مهمة موجودة، ولا يحذف النص القديم (مسار رجوع آمن).
            await _migrateLegacyBroadcastJobs();
          }
          if (from < 6) {
            // 6 — جدول سجل عمليات استيراد الكروت (card_import_logs): إضافي بالكامل، بلا مساس أي بيانات قائمة.
            await _createCardImportLogsTable();
          }
          await _applySqlitePragmas();
        },
        beforeOpen: (details) async {
          await _ensureTransferTemplateColumns();
          await _createIdempotencyIndexes();
          await _createPerformanceIndexes();
          await _createBroadcastTables();
          await _createCardImportLogsTable();
          await _ensureBroadcastColumns();
          // مؤقّت أمان idempotent: يغطّي أي ملف قاعدة لم يمرّ بمسار الترقية.
          await _migrateLegacyBroadcastJobs();
          await _applySqlitePragmas();
        },
      );

  Future<void> _ensureTransferTemplateColumns() async {
    await _addColumnIfMissing(
        'incoming_messages', 'last_attempt_at', 'INTEGER');
    await _addColumnIfMissing('transfer_templates', 'wallet_id', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'priority',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing('transfer_templates', 'sample_body', 'TEXT');
    await _addColumnIfMissing('transfer_templates', 'sender_code', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'identifier_kind',
      "TEXT NOT NULL DEFAULT 'phone'",
    );
    // Wallets/POS video-match additions — self-healing via beforeOpen, so no
    // separate schemaVersion bump is needed for these.
    await _addColumnIfMissing('transfer_templates', 'pos_id', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'sender_name_label',
      'TEXT',
    );
    await _addColumnIfMissing('transfer_templates', 'note_label', 'TEXT');
    await _addColumnIfMissing(
      'transfer_templates',
      'require_reference',
      'INTEGER NOT NULL DEFAULT 1',
    );
  }

  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String typeSql,
  ) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    final exists = rows.any((r) => r.read<String>('name') == column);
    if (exists) return;
    await customStatement('ALTER TABLE $table ADD COLUMN $column $typeSql');
  }

  /// Unique indexes (idempotency). Partial indexes allow multiple NULLs/empties.
  Future<void> _createIdempotencyIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_identifiers_value '
      'ON customer_identifiers (value)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_serial_number '
      'ON cards (serial_number)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_secret_code '
      'ON cards (secret_code) '
      "WHERE secret_code IS NOT NULL AND secret_code != ''",
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_reservation_id '
      'ON cards (reservation_id) WHERE reservation_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_incoming_messages_external_reference '
      'ON incoming_messages (external_reference) '
      'WHERE external_reference IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_reference '
      'ON transactions (reference) WHERE reference IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_card_id '
      'ON sales (card_id)',
    );
  }

  /// Hot-path indexes for message delivery, recovery, balances, inventory.
  Future<void> _createPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_entity '
      'ON audit_logs (entity_type, entity_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred '
      'ON audit_logs (occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_incoming_messages_status '
      'ON incoming_messages (status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_incoming_messages_received '
      'ON incoming_messages (received_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_incoming_messages_dispatch '
      'ON incoming_messages (status, last_attempt_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_customer '
      'ON transactions (customer_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_created '
      'ON transactions (created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_customer '
      'ON sales (customer_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_created '
      'ON sales (created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_category_status '
      'ON cards (category_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customer_identifiers_customer '
      'ON customer_identifiers (customer_id)',
    );
  }

  Future<void> _createBroadcastTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS broadcast_jobs ('
      'id TEXT NOT NULL PRIMARY KEY,'
      'body TEXT NOT NULL,'
      'status TEXT NOT NULL,'
      'created_at INTEGER NOT NULL,'
      'confirmed_at INTEGER,'
      'completed_at INTEGER,'
      'fingerprint TEXT'
      ')',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS broadcast_recipients ('
      'job_id TEXT NOT NULL,'
      'customer_id TEXT NOT NULL,'
      'position INTEGER NOT NULL DEFAULT 0,'
      'phone TEXT NOT NULL,'
      'display_name TEXT NOT NULL,'
      'status TEXT NOT NULL,'
      'error_code TEXT,'
      'attempts INTEGER NOT NULL DEFAULT 0,'
      'sent_at INTEGER,'
      'PRIMARY KEY (job_id, customer_id)'
      ')',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_broadcast_recipients_job '
      'ON broadcast_recipients (job_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_broadcast_jobs_fingerprint '
      'ON broadcast_jobs (fingerprint) WHERE fingerprint IS NOT NULL',
    );
  }

  /// WP-S4 (D8) — جدول سجل عمليات استيراد الكروت.
  ///
  /// يُنشأ بـSQL مباشر ويُقرأ عبر مستودع مخصوص
  /// (`LocalCardImportLogRepository`), وذلك لأن ملف الـDrift المولّد
  /// (`app_database.g.dart`) لا يُعاد توليده بلا Flutter SDK محليًا.
  /// الترميز: الطوابع الزمنية INTEGER بثواني Unix (UTC)
  /// مطابقةً لترميز Drift الافتراضي.
  Future<void> _createCardImportLogsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS card_import_logs ('
      'id TEXT NOT NULL PRIMARY KEY,'
      'file_name TEXT NOT NULL,'
      'file_kind TEXT NOT NULL,'
      'status TEXT NOT NULL,'
      'total_rows INTEGER NOT NULL DEFAULT 0,'
      'accepted_count INTEGER NOT NULL DEFAULT 0,'
      'duplicate_count INTEGER NOT NULL DEFAULT 0,'
      'rejected_count INTEGER NOT NULL DEFAULT 0,'
      'category_id TEXT,'
      'category_name TEXT,'
      'failure_reason TEXT,'
      'rejected_details TEXT,'
      'started_at INTEGER NOT NULL,'
      'finished_at INTEGER'
      ')',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_card_import_logs_started '
      'ON card_import_logs (started_at)',
    );
  }

  /// أعمدة جداول البث التي أُضيفت بعد أول إصدار لها — إضافية وidempotent.
  Future<void> _ensureBroadcastColumns() async {
    await _addColumnIfMissing(
      'broadcast_recipients',
      'position',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// ينقل مهام البث من `app_settings['broadcast_jobs']` إلى الجداول المسمّاة.
  ///
  /// idempotent بالكامل: لا يُدرج مهمة معرّفها موجود أصلًا (فلا يكتب فوق تقدم
  /// مهمة جارية ولا يكرّرها)، ولا يحذف النص القديم حتى يبقى مسار رجوع كامل.
  /// الصفوف تُقرأ من app_settings القديم فقط عند اللزوم، ولا يُقرأ وقت التشغيل.
  Future<void> _migrateLegacyBroadcastJobs() async {
    final List<QueryRow> rows;
    try {
      rows = await customSelect(
        "SELECT value FROM app_settings WHERE key = 'broadcast_jobs' LIMIT 1",
      ).get();
    } catch (_) {
      return; // لا جدول إعدادات بعد (قاعدة جديدة تكفّلها onCreate).
    }
    if (rows.isEmpty) return;
    final raw = rows.first.read<String?>('value');
    if (raw == null || raw.trim().isEmpty) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // نص قديم تالف لا يوقف فتح القاعدة.
    }
    if (decoded is! Map) return;
    final jobs = decoded['jobs'];
    if (jobs is! List) return;

    for (final row in jobs) {
      if (row is! Map) continue;
      final job = Map<String, dynamic>.from(row);
      final id = (job['id'] ?? '').toString().trim();
      final body = (job['body'] ?? '').toString();
      final status = (job['status'] ?? '').toString().trim();
      final createdAt = DateTime.tryParse((job['createdAt'] ?? '').toString());
      if (id.isEmpty || status.isEmpty || createdAt == null) continue;

      final exists = await (select(broadcastJobs)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      if (exists != null) continue;

      await into(broadcastJobs).insert(
        BroadcastJobsCompanion.insert(
          id: id,
          body: body,
          status: status,
          createdAt: createdAt.toUtc(),
          confirmedAt: Value(_dateOrNull(job['confirmedAt'])),
          completedAt: Value(_dateOrNull(job['completedAt'])),
          fingerprint: Value(_trimOrNull(job['fingerprint'])),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      final recipients = job['recipients'];
      if (recipients is! List) continue;
      for (var index = 0; index < recipients.length; index++) {
        final item = recipients[index];
        if (item is! Map) continue;
        final recipient = Map<String, dynamic>.from(item);
        final customerId = (recipient['customerId'] ?? '').toString().trim();
        final state = (recipient['status'] ?? '').toString().trim();
        if (customerId.isEmpty || state.isEmpty) continue;
        await into(broadcastRecipients).insert(
          BroadcastRecipientsCompanion.insert(
            jobId: id,
            customerId: customerId,
            position: Value(index),
            phone: (recipient['phone'] ?? '').toString().trim(),
            displayName: (recipient['displayName'] ?? '').toString(),
            status: state,
            errorCode: Value(_trimOrNull(recipient['errorCode'])),
            attempts: Value(int.tryParse('${recipient['attempts'] ?? 0}') ?? 0),
            sentAt: Value(_dateOrNull(recipient['sentAt'])),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  String? _trimOrNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  DateTime? _dateOrNull(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toUtc();
  }

  /// WAL + reasonable sync for concurrent readers during recovery ticks.
  Future<void> _applySqlitePragmas() async {
    await customStatement('PRAGMA journal_mode=WAL');
    await customStatement('PRAGMA synchronous=NORMAL');
    await customStatement('PRAGMA temp_store=MEMORY');
  }
}
