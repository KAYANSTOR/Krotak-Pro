import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/promotion.dart';
import 'package:net_app/domain/services/local_promotion_catalog.dart';

void main() {
  late AppDatabase database;
  late LocalPromotionCatalog catalog;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    catalog = LocalPromotionCatalog(
      settings: LocalSettingsRepository(database),
      clock: FixedClock(DateTime(2026, 9, 17, 12)),
      ids: SequentialIdGenerator(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('create then update persists title and threshold', () async {
    final created = await catalog.create(
      title: 'حملة رمضان',
      thresholdMinorUnits: 5000000,
      rewardCategoryId: 'cat-100',
    );
    expect(created, isA<Success<Promotion>>());
    final promo = (created as Success<Promotion>).value;

    final updated = await catalog.update(
      id: promo.id,
      title: 'حملة العيد',
      thresholdMinorUnits: 7000000,
      rewardCategoryId: 'cat-200',
      notes: 'محدّث',
    );
    expect(updated, isA<Success<Promotion>>());

    final listed = await catalog.listAll();
    final items = (listed as Success<List<Promotion>>).value;
    expect(items, hasLength(1));
    expect(items.single.title, 'حملة العيد');
    expect(items.single.thresholdMinorUnits, 7000000);
    expect(items.single.rewardCategoryId, 'cat-200');
    expect(items.single.notes, 'محدّث');
  });

  test('update missing promotion fails', () async {
    final r = await catalog.update(
      id: 'missing',
      title: 'x',
      thresholdMinorUnits: 100,
      rewardCategoryId: 'cat',
    );
    expect(r, isA<Failure<Promotion>>());
    expect((r as Failure<Promotion>).error.code, 'promo_not_found');
  });

  test('create rejects empty title', () async {
    final r = await catalog.create(
      title: '  ',
      thresholdMinorUnits: 100,
      rewardCategoryId: 'cat',
    );
    expect(r, isA<Failure<Promotion>>());
    expect((r as Failure<Promotion>).error.code, 'invalid_title');
  });
}
