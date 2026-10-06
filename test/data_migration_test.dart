import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide
        AuditLog,
        Card,
        CardCategory,
        Customer,
        CustomerIdentifier,
        IncomingMessage,
        Sale,
        Transaction,
        TransferTemplate;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';

/// ترحيل قاعدة بيانات حقيقية من نسخة أقدم إلى النسخة الحالية.
///
/// لا نكتفي بفحص `schemaVersion` على قاعدة جديدة. نُنشئ قاعدة بالنسخة الحالية،
/// نكتب فيها بيانات، ثم نُعيدها فعلًا إلى صيغة أقدم (بإزالة الأعمدة والفهارس التي
/// تضيفها خطوات الترحيل الموثّقة في `AppDatabase.migration`) ونخفض `user_version`.
/// ثم يفتحها التطبيق، فتمرّ بمسار `onUpgrade` الحقيقي — ونتحقق من:
/// الترقية + بقاء البيانات + اكتمال المخطط + تشغيل التطبيق عليها.
///
/// لا تُخترع أي بنية غير موجودة في الكود.
void main() {
  late Directory workDir;
  late String dbPath;

  /// الأعمدة التي تضيفها `_ensureTransferTemplateColumns` عند الترقية/الفتح.
  const addedColumns = <String, List<String>>{
    'incoming_messages': ['last_attempt_at'],
    'transfer_templates': [
      'wallet_id',
      'priority',
      'sample_body',
      'sender_code',
      'identifier_kind',
      'pos_id',
      'sender_name_label',
      'note_label',
      'require_reference',
    ],
    'broadcast_recipients': ['position'],
  };

  const idempotencyIndexes = <String>[
    'idx_customer_identifiers_value',
    'idx_cards_serial_number',
    'idx_cards_secret_code',
    'idx_cards_reservation_id',
    'idx_incoming_messages_external_reference',
    'idx_transactions_reference',
    'idx_sales_card_id',
  ];

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('krotak-migration');
    dbPath = '${workDir.path}/krotak.sqlite';
  });

  tearDown(() {
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
  });

  /// Seeds data through the real Drift API (correct DateTime encoding), which
  /// also materialises the current schema on disk.
  Future<void> seedLegacyRows() async {
    final db = AppDatabase(NativeDatabase(File(dbPath)));
    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            id: 'legacy-customer',
            displayName: 'عميل قديم',
            status: 'active',
            createdAt: DateTime(2026, 1, 2),
            updatedAt: DateTime(2026, 1, 2),
          ),
        );
    await db.into(db.customerIdentifiers).insert(
          CustomerIdentifiersCompanion.insert(
            id: 'legacy-identifier',
            customerId: 'legacy-customer',
            type: 'phoneNumber',
            value: '733111222',
          ),
        );
    await db.into(db.cards).insert(
          CardsCompanion.insert(
            id: 'legacy-card',
            categoryId: 'legacy-category',
            serialNumber: 'LEGACY-SN-1',
            secretCode: 'LEGACY-SECRET-1',
            status: 'available',
          ),
        );
    await db.into(db.incomingMessages).insert(
          IncomingMessagesCompanion.insert(
            id: 'legacy-message',
            sender: 'bank',
            body: 'transfer 200 to 733111222 ref LEGACY-R1',
            receivedAt: DateTime(2026, 1, 2),
            status: 'processed',
          ),
        );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'legacy-tx',
            type: 'deposit',
            status: 'completed',
            amountMinorUnits: 20000,
            currencyCode: 'YER',
            createdAt: DateTime(2026, 1, 2),
            customerId: const Value('legacy-customer'),
            reference: const Value('legacy-ref-1'),
          ),
        );
    await db.close();
  }

  /// Opens the on-disk database with the current app, but first rewinds the file
  /// to a genuinely older shape inside the same open — so `onUpgrade` is what
  /// the app actually hits, exactly like a real upgrade from the store build.
  Future<AppDatabase> openUpgrading({
    required int userVersion,
    List<String> legacyIndexSql = const [],
  }) {
    var rewound = false;
    return Future.value(
      AppDatabase(
        NativeDatabase(
          File(dbPath),
          setup: (raw) async {
            if (rewound) return;
            rewound = true;
            final tables = raw.select(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'cards'",
            );
            if (tables.isEmpty) return;

            // 1. الفهارس أولًا: SQLite يرفض حذف عمود ما زال فهرس يشير إليه.
            final indexes = raw.select(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name NOT LIKE 'sqlite_%'",
            );
            for (final row in indexes) {
              raw.execute('DROP INDEX IF EXISTS ${row['name']}');
            }

            // 2. الأعمدة التي أضافتها خطوات الترقية لاحقًا.
            for (final entry in addedColumns.entries) {
              for (final column in entry.value) {
                final info = raw.select('PRAGMA table_info(${entry.key})');
                final exists = info.any((row) => row['name'] == column);
                if (exists) {
                  raw.execute(
                    'ALTER TABLE ${entry.key} DROP COLUMN $column',
                  );
                }
              }
            }

            // 3. فهارس النسخة القديمة كما كانت فعلًا.
            for (final sql in legacyIndexSql) {
              raw.execute(sql);
            }

            // 4. أخيرًا: نسخة المخطط القديمة ليأخذ التطبيق مسار الترقية.
            raw.userVersion = userVersion;
          },
        ),
      ),
    );
  }

  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<Set<String>> columnsOf(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<int> userVersion(AppDatabase db) async {
    final rows = await db.customSelect('PRAGMA user_version').get();
    return rows.first.read<int>('user_version');
  }

  test('v1 database upgrades to the current schema and preserves every row',
      () async {
    await seedLegacyRows();

    final upgraded = await openUpgrading(userVersion: 1);
    addTearDown(upgraded.close);

    // 1. الأعمدة التي أضافها المسار القديم عادت.
    expect(await columnsOf(upgraded, 'incoming_messages'),
        contains('last_attempt_at'));
    expect(
      await columnsOf(upgraded, 'transfer_templates'),
      containsAll(addedColumns['transfer_templates']!),
    );

    // 2. كل الفهارس الفريدة (منع التكرار) عادت.
    expect(await indexNames(upgraded), containsAll(idempotencyIndexes));

    // 3. البيانات القديمة سليمة ولم تُحذف.
    final customers = await upgraded.select(upgraded.customers).get();
    expect(customers.single.id, 'legacy-customer');
    expect(customers.single.displayName, 'عميل قديم');
    expect(customers.single.createdAt, DateTime(2026, 1, 2));
    final identifiers =
        await upgraded.select(upgraded.customerIdentifiers).get();
    expect(identifiers.single.value, '733111222');
    final cards = await upgraded.select(upgraded.cards).get();
    expect(cards.single.serialNumber, 'LEGACY-SN-1');
    expect(cards.single.secretCode, 'LEGACY-SECRET-1');
    final messages = await upgraded.select(upgraded.incomingMessages).get();
    expect(messages.single.id, 'legacy-message');
    expect(messages.single.status, 'processed');
    final transactions = await upgraded.select(upgraded.transactions).get();
    expect(transactions.single.reference, 'legacy-ref-1');
    expect(transactions.single.customerId, 'legacy-customer');

    // 4. نسخة المخطط أصبحت الحالية.
    expect(await userVersion(upgraded), 5);
    // جداول البث المسمّاة موجودة بعد الترقية.
    expect(await columnsOf(upgraded, 'broadcast_jobs'), contains('fingerprint'));
    expect(
      await columnsOf(upgraded, 'broadcast_recipients'),
      contains('position'),
    );

    // 5. الكتابة بعد الترقية تعمل على الأعمدة المضافة (يقرأها المستودع الحقيقي
    //    بـ raw SQL لا عبر Drift).
    final templates = LocalTransferTemplateRepository(upgraded);
    final saved = await templates.save(
      const TransferTemplate(
        id: 'after-upgrade',
        name: 'قالب بعد الترقية',
        pattern: '{qty} كرت {amount} {phone}',
        isActive: true,
        walletId: 'wallet-1',
        posId: 'pos-1',
        requireReference: false,
        sampleBody: '1 كرت 100 779776919',
        priority: 4,
      ),
    );
    expect(saved, isA<Success<void>>());
    final reloaded = await templates.findById('after-upgrade');
    final template = (reloaded as Success<TransferTemplate?>).value!;
    expect(template.posId, 'pos-1');
    expect(template.walletId, 'wallet-1');
    expect(template.requireReference, isFalse);
    expect(template.sampleBody, '1 كرت 100 779776919');
    expect(template.priority, 4);
  });

  test(
      'a database carrying the legacy unique secret_code index upgrades and '
      'accepts serial-only cards afterwards', () async {
    await seedLegacyRows();

    final upgraded = await openUpgrading(
      userVersion: 3,
      legacyIndexSql: const [
        'CREATE UNIQUE INDEX idx_cards_secret_code ON cards (secret_code)',
      ],
    );
    addTearDown(upgraded.close);

    // البيانات القديمة محفوظة.
    final cards = await upgraded.select(upgraded.cards).get();
    expect(cards.single.secretCode, 'LEGACY-SECRET-1');

    // الترقية أزالت الفهرس القديم واستبدلته بفهرس جزئي، فيمكن الآن تعايش
    // كرتين بلا رمز سري ('' ) — وهو سبب الترقية رقم 4.
    await upgraded.into(upgraded.cards).insert(
          CardsCompanion.insert(
            id: 'serial-only-1',
            categoryId: 'legacy-category',
            serialNumber: 'SERIAL-ONLY-1',
            secretCode: '',
            status: 'available',
          ),
        );
    await upgraded.into(upgraded.cards).insert(
          CardsCompanion.insert(
            id: 'serial-only-2',
            categoryId: 'legacy-category',
            serialNumber: 'SERIAL-ONLY-2',
            secretCode: '',
            status: 'available',
          ),
        );
    expect(await upgraded.select(upgraded.cards).get(), hasLength(3));

    // وما زال الرمز السري غير الفارغ محميًا من التكرار.
    await expectLater(
      upgraded.into(upgraded.cards).insert(
            CardsCompanion.insert(
              id: 'duplicate-secret',
              categoryId: 'legacy-category',
              serialNumber: 'SERIAL-ONLY-3',
              secretCode: 'LEGACY-SECRET-1',
              status: 'available',
            ),
          ),
      throwsA(isA<Exception>()),
    );

    expect(await userVersion(upgraded), 5);
  });

  test('legacy broadcast JSON migrates into the typed tables exactly once',
      () async {
    await seedLegacyRows();
    final legacyPayload = jsonEncode({
      'jobs': [
        {
          'id': 'legacy-bcast-1',
          'body': 'رسالة جماعية قديمة',
          'status': 'partiallyFailed',
          'createdAt': DateTime.utc(2026, 1, 20, 10).toIso8601String(),
          'confirmedAt': DateTime.utc(2026, 1, 20, 10, 5).toIso8601String(),
          'completedAt': DateTime.utc(2026, 1, 20, 10, 30).toIso8601String(),
          'fingerprint': 'legacy-fingerprint',
          'recipients': [
            {
              'customerId': 'legacy-customer',
              'phone': '733111222',
              'displayName': 'عميل قديم',
              'status': 'sent',
              'attempts': 1,
              'sentAt': DateTime.utc(2026, 1, 20, 10, 10).toIso8601String(),
            },
            {
              'customerId': 'legacy-second',
              'phone': '733111333',
              'displayName': 'عميل ثانٍ',
              'status': 'failed',
              'errorCode': 'sms_send_failed',
              'attempts': 2,
            },
          ],
        },
      ],
    });
    final seed = AppDatabase(NativeDatabase(File(dbPath)));
    await seed.into(seed.appSettings).insert(
          AppSettingsCompanion.insert(
            key: 'broadcast_jobs',
            value: legacyPayload,
            updatedAt: DateTime.utc(2026, 1, 20),
          ),
          mode: InsertMode.insertOrReplace,
        );
    await seed.close();

    // ترقية حقيقية من نسخة 4 (بلا عمود position) مع نص البث القديم في الإعدادات.
    final upgraded = await openUpgrading(userVersion: 4);
    addTearDown(upgraded.close);
    expect(await userVersion(upgraded), 5);

    final jobs = await upgraded.select(upgraded.broadcastJobs).get();
    expect(jobs, hasLength(1));
    expect(jobs.single.id, 'legacy-bcast-1');
    expect(jobs.single.status, 'partiallyFailed');
    expect(jobs.single.createdAt.toUtc(), DateTime.utc(2026, 1, 20, 10));
    expect(jobs.single.fingerprint, 'legacy-fingerprint');
    final recipients = await (upgraded.select(upgraded.broadcastRecipients)
          ..orderBy([(table) => OrderingTerm(expression: table.position)]))
        .get();
    expect(recipients, hasLength(2));
    expect(recipients.first.customerId, 'legacy-customer');
    expect(recipients.first.status, 'sent');
    expect(recipients.first.sentAt!.toUtc(), DateTime.utc(2026, 1, 20, 10, 10));
    expect(recipients.last.customerId, 'legacy-second');
    expect(recipients.last.position, 1);
    expect(recipients.last.errorCode, 'sms_send_failed');
    expect(recipients.last.attempts, 2);

    // النص القديم باقٍ كمسار رجوع، لكنه ليس مصدرًا وقت التشغيل.
    final legacy = await (upgraded.select(upgraded.appSettings)
          ..where((table) => table.key.equals('broadcast_jobs')))
        .getSingle();
    expect(legacy.value, legacyPayload);

    await upgraded.close();

    // إعادة الفتح (نسخة 5) تمرّ بمسار الترحيل نفسه: لا تكرار ولا كتابة فوق مهمة.
    final reopened = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(reopened.close);
    expect(await reopened.select(reopened.broadcastJobs).get(), hasLength(1));
    expect(
      await reopened.select(reopened.broadcastRecipients).get(),
      hasLength(2),
    );

    // ولو تقدمت المهمة في الجداول فالنص القديم لا يكتب فوقها.
    await (reopened.update(reopened.broadcastJobs)
          ..where((table) => table.id.equals('legacy-bcast-1')))
        .write(const BroadcastJobsCompanion(status: Value('completed')));
    final again = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(again.close);
    final after = await (again.select(again.broadcastJobs)
          ..where((table) => table.id.equals('legacy-bcast-1')))
        .getSingle();
    expect(after.status, 'completed', reason: 'الترحيل إضافي ولا يكتب فوق الحالة');
  });

  test('the application boots against a migrated older database', () async {
    await seedLegacyRows();

    final database = await openUpgrading(userVersion: 1);
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('${workDir.path}/backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    // البيانات المحفوظة قبل الترقية مقروءة عبر الواجهات الحقيقية.
    final found = await container.customers.findByIdentifier('733111222');
    expect(found, isA<Success<Customer?>>());
    expect((found as Success<Customer?>).value?.displayName, 'عميل قديم');

    // وطبقة الرسائل تعمل على القاعدة المرحّلة.
    final recent = await container.messages.listRecent(limit: 10);
    expect(recent, isA<Success<List<IncomingMessage>>>());
    expect(
      (recent as Success<List<IncomingMessage>>).value.single.id,
      'legacy-message',
    );

    // والكتالوج يقرأ الكرت القديم كما هو.
    final card = await container.cards.findById('legacy-card');
    expect((card as Success<Card?>).value?.serialNumber, 'LEGACY-SN-1');
  });
}
