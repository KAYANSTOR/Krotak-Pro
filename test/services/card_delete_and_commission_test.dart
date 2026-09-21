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
  DateTime now() => DateTime.utc(2026, 9, 20, 12);
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
  late LocalCardCatalogService catalog;

  setUp(() {
    cards = InMemoryCardRepository();
    categories = _MemCategories();
    audit = InMemoryAuditLogRepository();
    catalog = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: audit,
      unitOfWork: InMemoryUnitOfWork(),
      clock: _Clock(),
      ids: _Ids(),
    );
  });

  Future<void> seedCategory({String id = 'cat-1'}) async {
    await categories.save(
      CardCategory(
        id: id,
        name: '100',
        faceValue: const Money(minorUnits: 10000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
  }

  Future<List<Card>> stocked() async {
    final listed = await cards.listAll();
    return (listed as Success<List<Card>>).value;
  }

  Future<void> seedCards(int count) async {
    await seedCategory();
    await catalog.importCards(
      categoryId: 'cat-1',
      drafts: [
        for (var i = 1; i <= count; i++)
          CardImportDraft(serialNumber: 'S$i', secretCode: 'P$i'),
      ],
    );
  }

  test('deleteCards removes the selected cards and logs an audit entry', () async {
    await seedCards(3);
    final before = await stocked();
    expect(before.length, 3);

    final result = await catalog.deleteCards(cardIds: [before.first.id]);

    expect(result, isA<Success<int>>());
    expect((result as Success<int>).value, 1);
    final after = await stocked();
    expect(after.length, 2);
    expect(after.any((c) => c.id == before.first.id), isFalse);
    expect(audit.logs.any((l) => l.action == 'cards_deleted'), isTrue);
  });

  test('deleteCards removes several cards in one call', () async {
    await seedCards(4);
    final before = await stocked();
    final ids = before.take(3).map((c) => c.id).toList();

    final result = await catalog.deleteCards(cardIds: ids);

    expect((result as Success<int>).value, 3);
    expect((await stocked()).length, 1);
  });

  test('deleteCards rejects an empty selection', () async {
    final result = await catalog.deleteCards(cardIds: const ['', '  ']);
    expect(result, isA<Failure<int>>());
    expect((result as Failure<int>).error.code, 'no_cards_selected');
  });

  test('deleteCards reports unknown ids instead of failing silently', () async {
    final result = await catalog.deleteCards(cardIds: const ['missing-card']);
    expect(result, isA<Failure<int>>());
    expect((result as Failure<int>).error.code, 'card_not_found');
  });

  test('saveCategory keeps the commission percent when editing', () async {
    final result = await catalog.saveCategory(
      const CardCategory(
        id: 'cat-9',
        name: 'كرت 200',
        faceValue: Money(minorUnits: 20000, currencyCode: 'YER'),
        isActive: true,
        commissionPercentBps: 750,
      ),
    );

    expect(result, isA<Success<CardCategory>>());
    final saved = (result as Success<CardCategory>).value;
    expect(saved.commissionPercentBps, 750);
    expect(categories.map['cat-9']?.commissionPercentBps, 750);
  });

  test('deleteCards tombstones sold cards instead of hard-deleting', () async {
    await seedCards(2);
    final all = await stocked();
    final soldCard = all.first;
    await cards.save(
      Card(
        id: soldCard.id,
        categoryId: soldCard.categoryId,
        serialNumber: soldCard.serialNumber,
        secretCode: soldCard.secretCode,
        status: CardStatus.sold,
      ),
    );

    final result = await catalog.deleteCards(cardIds: [soldCard.id]);
    expect(result, isA<Success<int>>());
    expect((result as Success<int>).value, 1);

    final after = await cards.findById(soldCard.id);
    final card = (after as Success<Card?>).value;
    expect(card, isNotNull);
    expect(card!.status, CardStatus.disabled);
    expect(audit.logs.any((l) => l.action == 'cards_tombstoned'), isTrue);
  });

  test('deleteCards rejects reserved-only selection', () async {
    await seedCards(1);
    final all = await stocked();
    final card = all.single;
    await cards.save(
      Card(
        id: card.id,
        categoryId: card.categoryId,
        serialNumber: card.serialNumber,
        secretCode: card.secretCode,
        status: CardStatus.reserved,
        reservation: CardReservation(
          reservationId: 'r1',
          reservedAt: DateTime.utc(2026, 9, 21),
          expiresAt: DateTime.utc(2026, 9, 22),
        ),
      ),
    );

    final result = await catalog.deleteCards(cardIds: [card.id]);
    expect(result, isA<Failure<int>>());
    expect((result as Failure<int>).error.code, 'card_reserved');
  });
}
