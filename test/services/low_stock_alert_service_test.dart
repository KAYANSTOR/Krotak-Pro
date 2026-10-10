import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_low_stock_alert_service.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  group('LocalLowStockAlertService', () {
    late _MemSettings settings;
    late _MemCategories categories;
    late InMemoryCardRepository cards;
    late LocalLowStockAlertService service;
    final clock = FixedClock(DateTime.utc(2026, 9, 20, 21));

    setUp(() {
      // نصّ القالب من مصدره الوحيد (الإعدادات) — لا نص بديل وقت الإرسال.
      settings = _MemSettings()
        ..values.addAll(OutboundTemplateCatalog.initialBodies());
      categories = _MemCategories();
      cards = InMemoryCardRepository();
      service = LocalLowStockAlertService(
        settings: settings,
        categories: categories,
        cards: cards,
        clock: clock,
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

    test('renders the operator alert from the registered template only', () async {
      // قرارات المالك §7: هذا تنبيه داخلي للمشغّل — لا يمر على MessageSender
      // ولا يُرسل لأي رقم عميل؛ رسالة العميل تأتي من مسار الإيداع وحده.
      final body = await service.renderOperatorBody(const [
        LowStockAlert(categoryId: 'cat-1', categoryName: '100', available: 0),
      ]);
      expect(body, contains('100'));
      expect(body, contains('0'));
      expect(body, isNot(contains('الإدارة')));
    });

    test('falls back to the built-in operator summary when the template is absent', () async {
      final bare = LocalLowStockAlertService(
        settings: _MemSettings(),
        categories: categories,
        cards: cards,
        clock: clock,
      );
      final body = await bare.renderOperatorBody(const [
        LowStockAlert(categoryId: 'cat-1', categoryName: '100', available: 0),
      ]);
      expect(body, contains('كرت 100 (0)'));
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
      expect(notifier.lastBody, contains('100'));
      expect(notifier.lastBody, contains('0'));

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
      expect(notifier.lastBody, contains('1'));

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

