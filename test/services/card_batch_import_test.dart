import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Card, CardCategory;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalAuditLogRepository auditLogs;
  late LocalCardCatalogService catalog;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    catalog = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: DriftUnitOfWork(database),
      clock: FixedClock(DateTime(2026, 9, 13)),
      ids: SequentialIdGenerator(),
    );
    await catalog.saveCategory(
      const CardCategory(
        id: 'cat-200',
        name: '200',
        faceValue: Money(minorUnits: 200, currencyCode: 'YER'),
        isActive: true,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('imports a large batch with a single progress sweep and no N+1 lookups', () async {
    final drafts = [
      for (var i = 0; i < 450; i++)
        CardImportDraft(serialNumber: 'S-$i', secretCode: 'P-$i'),
    ];
    final ticks = <(int, int)>[];
    final result = await catalog.importCardsDetailed(
      categoryId: 'cat-200',
      drafts: drafts,
      onProgress: (done, total) => ticks.add((done, total)),
    );

    expect(result, isA<Success<CardImportReport>>());
    final report = (result as Success<CardImportReport>).value;
    expect(report.imported, 450);
    expect(report.skipped, 0);
    expect(ticks, isNotEmpty);
    expect(ticks.last.$1, 450);

    final stored = await cards.findByCategory('cat-200');
    expect((stored as Success<List<Card>>).value, hasLength(450));
  });

  test('skips existing serials and secrets without aborting valid rows', () async {
    await catalog.importCards(
      categoryId: 'cat-200',
      drafts: const [
        CardImportDraft(serialNumber: 'S-1', secretCode: 'P-1'),
      ],
    );

    final result = await catalog.importCardsDetailed(
      categoryId: 'cat-200',
      drafts: const [
        CardImportDraft(serialNumber: 'S-1', secretCode: 'P-new'),
        CardImportDraft(serialNumber: 'S-2', secretCode: 'P-1'),
        CardImportDraft(serialNumber: 'S-3', secretCode: 'P-3'),
      ],
    );

    expect(result, isA<Success<CardImportReport>>());
    final report = (result as Success<CardImportReport>).value;
    expect(report.imported, 1);
    expect(report.skipped, 2);
    expect(report.hasErrors, isTrue);

    final stored = await cards.findByCategory('cat-200');
    expect((stored as Success<List<Card>>).value.map((e) => e.serialNumber), containsAll(['S-1', 'S-3']));
  });

  test('rejects a batch when every row is invalid or duplicate', () async {
    await catalog.importCards(
      categoryId: 'cat-200',
      drafts: const [
        CardImportDraft(serialNumber: 'S-1', secretCode: 'P-1'),
      ],
    );
    final result = await catalog.importCardsDetailed(
      categoryId: 'cat-200',
      drafts: const [
        CardImportDraft(serialNumber: 'S-1', secretCode: 'P-9'),
      ],
    );
    expect(result, isA<Failure<CardImportReport>>());
    expect((result as Failure<CardImportReport>).error.code, 'card_import_rejected');
  });
}
