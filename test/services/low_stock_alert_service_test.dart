import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_low_stock_alert_service.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  group('LocalLowStockAlertService', () {
    late _MemSettings settings;
    late _MemCategories categories;
    late InMemoryCardRepository cards;
    late _MemSender sender;
    late LocalLowStockAlertService service;
    final clock = FixedClock(DateTime.utc(2026, 9, 20, 21));

    setUp(() {
      settings = _MemSettings();
      categories = _MemCategories();
      cards = InMemoryCardRepository();
      sender = _MemSender();
      service = LocalLowStockAlertService(
        settings: settings,
        categories: categories,
        cards: cards,
        clock: clock,
        messageSender: sender,
      );
    });

    test('persists depleted category until cards are added', () async {
      await categories.save(_cat());
      await service.markDepleted(
        categoryId: 'cat-1',
        categoryName: '100',
        available: 0,
      );
      expect((await service.listActive()).single.categoryId, 'cat-1');

      await service.refreshFromInventory();
      expect((await service.listActive()).single.available, 0);

      await cards.save(
        const Card(
          id: 'c1',
          categoryId: 'cat-1',
          serialNumber: '111',
          secretCode: 'aaa',
          status: CardStatus.available,
        ),
      );
      await settings.save(
        AppSetting(
          key: SettingKeys.lowStockThreshold,
          value: '0',
          updatedAt: clock.now(),
        ),
      );
      final after = await service.refreshFromInventory();
      expect(after, isEmpty);
    });

    test('keeps alert when available stays at or below threshold', () async {
      await categories.save(_cat());
      await cards.save(
        const Card(
          id: 'c1',
          categoryId: 'cat-1',
          serialNumber: '111',
          secretCode: 'aaa',
          status: CardStatus.available,
        ),
      );
      final alerts = await service.refreshFromInventory();
      expect(alerts.single.available, 1);
    });

    test('sends a clear customer SMS instead of staying silent', () async {
      final sent = await service.notifyCustomer(
        destination: '777123456',
        categoryName: '100',
        available: 0,
      );
      expect(sent, isA<Success<void>>());
      expect(sender.bodies, hasLength(1));
      expect(sender.destinations.single, '777123456');
      expect(sender.bodies.single, contains('غير متوفرة'));
      expect(sender.bodies.single, contains('100'));
      expect(sender.bodies.single, contains('الإدارة'));
    });

    test('syncDeviceAlert publishes the live alert and clears it after refill', () async {
      final notifier = _MemNotifier();
      final synced = LocalLowStockAlertService(
        settings: settings,
        categories: categories,
        cards: cards,
        clock: clock,
        notifier: notifier,
      );
      await categories.save(_cat());

      await synced.syncDeviceAlert();
      expect(notifier.shows, 1);
      expect(notifier.clears, 0);
      expect(notifier.lastTitle, contains('تنبيه المخزون'));
      expect(notifier.lastBody, contains('كرت 100 (0)'));

      // تعبئة جزئية (ما دون العتبة): يبقى الإشعار ويُحدَّث نصه بالعدد الجديد.
      await cards.save(
        const Card(
          id: 'c1',
          categoryId: 'cat-1',
          serialNumber: '111',
          secretCode: 'aaa',
          status: CardStatus.available,
        ),
      );
      await synced.syncDeviceAlert();
      expect(notifier.shows, 2);
      expect(notifier.clears, 0);
      expect(notifier.lastBody, contains('كرت 100 (1)'));

      await settings.save(
        AppSetting(
          key: SettingKeys.lowStockThreshold,
          value: '1',
          updatedAt: clock.now(),
        ),
      );
      await synced.syncDeviceAlert();
      expect(notifier.clears, 1);
    });

    test('renderCustomerMessage substitutes placeholders', () {
      final text = service.renderCustomerMessage(
        categoryName: '200',
        available: 0,
        template: 'نفد {category} المتبقي {count}',
      );
      expect(text, 'نفد 200 المتبقي 0');
    });
  });
}

CardCategory _cat() => const CardCategory(
      id: 'cat-1',
      name: '100',
      faceValue: Money(minorUnits: 10000, currencyCode: 'YER'),
      isActive: true,
    );

final class _MemSettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final v = values[key];
    if (v == null) return const Success(null);
    return Success(AppSetting(key: key, value: v, updatedAt: DateTime.utc(2026, 9, 20)));
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
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

final class _MemNotifier implements StockAlertNotifier {
  int shows = 0;
  int clears = 0;
  String lastTitle = '';
  String lastBody = '';

  @override
  Future<void> show({required String title, required String body}) async {
    shows++;
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

final class _MemSender implements MessageSender {
  final destinations = <String>[];
  final bodies = <String>[];

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    destinations.add(destination);
    bodies.add(body);
    return const Success(null);
  }
}
