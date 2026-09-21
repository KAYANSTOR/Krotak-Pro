import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 17, 12);
}

final class _Ids implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) => '$prefix-${++n}';
}

final class _MemCategories implements CardCategoryRepository {
  final map = <String, CardCategory>{};

  @override
  Future<Result<CardCategory?>> findById(String id) async => Success(map[id]);

  @override
  Future<Result<List<CardCategory>>> listAll() async =>
      Success(map.values.toList(growable: false));

  @override
  Future<Result<void>> save(CardCategory category) async {
    map[category.id] = category;
    return const Success(null);
  }
}

void main() {
  late InMemoryCardRepository cards;
  late _MemCategories categories;
  late InMemoryAuditLogRepository audit;
  late InMemoryUnitOfWork uow;
  late LocalCardCatalogService catalog;

  setUp(() {
    cards = InMemoryCardRepository();
    categories = _MemCategories();
    audit = InMemoryAuditLogRepository();
    uow = InMemoryUnitOfWork();
    catalog = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: audit,
      unitOfWork: uow,
      clock: _Clock(),
      ids: _Ids(),
    );
  });

  Future<void> seedCategory() async {
    await categories.save(
      const CardCategory(
        id: 'cat-1',
        name: '100',
        faceValue: Money(minorUnits: 10000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
  }

  test('import serialAndPin batch', () async {
    await seedCategory();
    final r = await catalog.importCards(
      categoryId: 'cat-1',
      drafts: const [
        CardImportDraft(serialNumber: 'S1', secretCode: 'P1'),
        CardImportDraft(serialNumber: 'S2', secretCode: 'P2'),
      ],
    );
    expect(r, isA<Success<int>>());
    expect((r as Success<int>).value, 2);
  });

  test('import serialOnly batch allows empty secret', () async {
    await seedCategory();
    final r = await catalog.importCards(
      categoryId: 'cat-1',
      drafts: const [
        CardImportDraft(
          serialNumber: 'ONLY1',
          secretCode: '',
          format: CardImportFormat.serialOnly,
        ),
        CardImportDraft(
          serialNumber: 'ONLY2',
          secretCode: '',
          format: CardImportFormat.serialOnly,
        ),
      ],
    );
    expect(r, isA<Success<int>>());
    expect((r as Success<int>).value, 2);
    final listed = await cards.findBySerialNumber('ONLY1');
    final card = (listed as Success<Card?>).value!;
    expect(card.secretCode, isEmpty);
  });

  test('serialAndPin rejects empty secret', () async {
    await seedCategory();
    final r = await catalog.importCards(
      categoryId: 'cat-1',
      drafts: const [
        CardImportDraft(serialNumber: 'X', secretCode: ''),
      ],
    );
    expect(r, isA<Failure>());
  });
}
