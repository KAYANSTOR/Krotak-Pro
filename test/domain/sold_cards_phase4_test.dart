import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/sold_cards_service.dart';

import 'package:net_app/domain/repositories/repositories.dart';
import '../helpers/in_memory_repositories.dart';

final class _MemCategories implements CardCategoryRepository {
  final map = <String, CardCategory>{};
  @override
  Future<Result<CardCategory?>> findById(String id) async => Success(map[id]);
  @override
  Future<Result<List<CardCategory>>> listAll() async => Success(map.values.toList());
  @override
  Future<Result<void>> save(CardCategory category) async {
    map[category.id] = category;
    return const Success(null);
  }
}


final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 21, 12);
}

final class _Ids implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) => '$prefix-${++n}';
}

void main() {
  test('query joins sold cards with sales and exportCsv is stable', () async {
    final cards = InMemoryCardRepository();
    final sales = InMemorySaleRepository();
    final customers = InMemoryCustomerRepository();
    final categories = _MemCategories();
    final audits = InMemoryAuditLogRepository();

    await categories.save(
      CardCategory(
        id: 'cat-100',
        name: 'فئة 100',
        faceValue: const Money(minorUnits: 10000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    await customers.save(
      Customer(
        id: 'cust-1',
        displayName: 'أحمد',
        status: CustomerStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await cards.save(
      const Card(
        id: 'card-1',
        categoryId: 'cat-100',
        serialNumber: 'SN-1001',
        secretCode: 'SEC',
        status: CardStatus.sold,
      ),
    );
    await sales.save(
      Sale(
        id: 'sale-1',
        customerId: 'cust-1',
        cardId: 'card-1',
        amount: const Money(minorUnits: 10000, currencyCode: 'YER'),
        status: TransactionStatus.completed,
        createdAt: DateTime.utc(2026, 9, 20, 10),
      ),
    );

    final service = SoldCardsService(
      cards: cards,
      sales: sales,
      customers: customers,
      categories: categories,
      auditLogs: audits,
      unitOfWork: InMemoryUnitOfWork(),
      clock: _Clock(),
      ids: _Ids(),
    );

    final r = await service.query(const SoldCardsFilter());
    expect(r, isA<Success<List<SoldCardRow>>>());
    final rows = (r as Success<List<SoldCardRow>>).value;
    expect(rows.length, 1);
    expect(rows.first.card.serialNumber, 'SN-1001');
    expect(rows.first.customerName, 'أحمد');

    final csv = service.exportCsv(rows);
    expect(csv.contains('SN-1001'), isTrue);
    expect(csv.contains('فئة 100'), isTrue);
  });

  test('category filter narrows sold results', () async {
    final cards = InMemoryCardRepository();
    final sales = InMemorySaleRepository();
    final customers = InMemoryCustomerRepository();
    final categories = _MemCategories();
    final audits = InMemoryAuditLogRepository();

    for (final id in ['a', 'b']) {
      await categories.save(
        CardCategory(
          id: 'cat-$id',
          name: id,
          faceValue: const Money(minorUnits: 1000, currencyCode: 'YER'),
          isActive: true,
        ),
      );
      await cards.save(
        Card(
          id: 'card-$id',
          categoryId: 'cat-$id',
          serialNumber: 'S-$id',
          secretCode: 'x',
          status: CardStatus.sold,
        ),
      );
    }

    final service = SoldCardsService(
      cards: cards,
      sales: sales,
      customers: customers,
      categories: categories,
      auditLogs: audits,
      unitOfWork: InMemoryUnitOfWork(),
      clock: _Clock(),
      ids: _Ids(),
    );

    final r = await service.query(const SoldCardsFilter(categoryId: 'cat-a'));
    final rows = (r as Success<List<SoldCardRow>>).value;
    expect(rows.length, 1);
    expect(rows.single.card.serialNumber, 'S-a');
  });
}
