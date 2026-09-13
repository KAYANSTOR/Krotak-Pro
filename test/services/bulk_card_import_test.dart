import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Card, CardCategory;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/card_import_parser.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalAuditLogRepository auditLogs;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCardCatalogService catalogService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 13, 10));
    ids = SequentialIdGenerator();
    catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> createCategory() async {
    final result = await catalogService.saveCategory(
      const CardCategory(
        id: 'cat-500',
        name: 'Yemen Mobile 500',
        faceValue: Money(minorUnits: 50000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    expect(result, isA<Success<CardCategory>>());
  }

  test('parser skips header, blanks and reports per-line errors', () {
    const raw = '''
serial,secret
A-1,PIN-1

# comment
broken-line
A-1,PIN-DUP-SERIAL
A-2,PIN-1
A-3,PIN-3
''';
    final parsed = CardImportParser.parse(raw);
    expect(parsed.drafts.map((d) => d.serialNumber), ['A-1', 'A-3']);
    expect(parsed.errors, isNotEmpty);
  });

  test('imports a large batch in chunks and reports progress', () async {
    await createCategory();
    final drafts = [
      for (var i = 0; i < 450; i++)
        CardImportDraft(serialNumber: 'SN-$i', secretCode: 'SEC-$i'),
    ];
    final ticks = <(int, int)>[];
    final imported = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: drafts,
      onProgress: (processed, total) => ticks.add((processed, total)),
    );
    expect((imported as Success<int>).value, 450);
    expect(ticks.first, (0, 450));
    expect(ticks.last, (450, 450));
    final available = await cards.findAvailableByCategory('cat-500');
    expect((available as Success<List<Card>>).value, hasLength(450));
  });

  test('skips existing serials and secrets then imports only new cards', () async {
    await createCategory();
    final first = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'S-1'),
        CardImportDraft(serialNumber: 'A-2', secretCode: 'S-2'),
      ],
    );
    expect((first as Success<int>).value, 2);

    final second = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'S-NEW'),
        CardImportDraft(serialNumber: 'A-3', secretCode: 'S-2'),
        CardImportDraft(serialNumber: 'A-4', secretCode: 'S-4'),
      ],
    );
    expect((second as Success<int>).value, 1);
    final available = await cards.findAvailableByCategory('cat-500');
    expect(
      (available as Success<List<Card>>).value.map((c) => c.serialNumber),
      ['A-1', 'A-2', 'A-4'],
    );
  });

  test('fails when every draft already exists', () async {
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'S-1'),
      ],
    );
    final again = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'S-OTHER'),
      ],
    );
    expect((again as Failure<int>).error.code, 'duplicate_serial');
  });
}
