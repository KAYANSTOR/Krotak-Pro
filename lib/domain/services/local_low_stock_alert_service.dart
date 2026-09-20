import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'services.dart';

final class LowStockAlert {
  const LowStockAlert({
    required this.categoryId,
    required this.categoryName,
    required this.available,
  });

  final String categoryId;
  final String categoryName;
  final int available;
}

final class LocalLowStockAlertService {
  const LocalLowStockAlertService({
    required this.settings,
    required this.categories,
    required this.cards,
    required this.clock,
    this.messageSender,
  });

  final SettingsRepository settings;
  final CardCategoryRepository categories;
  final CardRepository cards;
  final Clock clock;
  final MessageSender? messageSender;

  static const defaultCustomerTemplate =
      'عذراً، كروت فئة {category} غير متوفرة حالياً (المتبقي: {count}). يرجى التواصل مع الإدارة.';

  Future<int> threshold() async {
    final raw = await settings.find(SettingKeys.lowStockThreshold);
    final value = raw is Success<AppSetting?> ? raw.value?.value : null;
    return SettingInt.read(value, defaultValue: SettingDefaults.lowStockThreshold);
  }

  Future<List<LowStockAlert>> listActive() async {
    return _readStored();
  }

  Future<List<LowStockAlert>> refreshFromInventory() async {
    final limit = await threshold();
    final cats = await categories.listAll();
    if (cats is Failure<List<CardCategory>>) return _readStored();
    final alerts = <LowStockAlert>[];
    for (final category in (cats as Success<List<CardCategory>>).value) {
      if (!category.isActive) continue;
      final available = await cards.findAvailableByCategory(category.id);
      if (available is Failure<List<Card>>) continue;
      final count = (available as Success<List<Card>>).value.length;
      if (count <= limit) {
        alerts.add(
          LowStockAlert(
            categoryId: category.id,
            categoryName: category.name,
            available: count,
          ),
        );
      }
    }
    await _writeStored(alerts);
    return alerts;
  }

  Future<void> markDepleted({
    required String categoryId,
    required String categoryName,
    int available = 0,
  }) async {
    final current = await _readStored();
    final next = [
      for (final a in current)
        if (a.categoryId != categoryId) a,
      LowStockAlert(
        categoryId: categoryId,
        categoryName: categoryName,
        available: available,
      ),
    ];
    await _writeStored(next);
  }

  String renderCustomerMessage({
    required String categoryName,
    required int available,
    String? template,
  }) {
    final raw = (template != null && template.trim().isNotEmpty)
        ? template
        : defaultCustomerTemplate;
    return raw
        .replaceAll('{category}', categoryName)
        .replaceAll('{count}', '$available')
        .replaceAll('{CARD_VALUE}', categoryName);
  }

  Future<String> loadCustomerTemplate() async {
    final found = await settings.find(SettingKeys.lowStockAlertTemplate);
    final raw = found is Success<AppSetting?> ? found.value?.value : null;
    if (raw != null && raw.trim().isNotEmpty) return raw;
    return defaultCustomerTemplate;
  }

  Future<Result<void>> notifyCustomer({
    required String destination,
    required String categoryName,
    int available = 0,
  }) async {
    final sender = messageSender;
    final dest = destination.trim();
    if (sender == null || dest.isEmpty) {
      return const Failure(
        AppFailure(code: 'low_stock_sms_skipped', message: 'No destination or sender'),
      );
    }
    final template = await loadCustomerTemplate();
    final body = renderCustomerMessage(
      categoryName: categoryName,
      available: available,
      template: template,
    );
    return sender.send(destination: dest, body: body);
  }

  Future<List<LowStockAlert>> _readStored() async {
    final found = await settings.find(SettingKeys.lowStockActiveJson);
    final raw = found is Success<AppSetting?> ? found.value?.value : null;
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            LowStockAlert(
              categoryId: '${item['id'] ?? ''}',
              categoryName: '${item['name'] ?? ''}',
              available: int.tryParse('${item['available'] ?? 0}') ?? 0,
            ),
      ].where((a) => a.categoryId.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeStored(List<LowStockAlert> alerts) async {
    final payload = jsonEncode([
      for (final a in alerts)
        {
          'id': a.categoryId,
          'name': a.categoryName,
          'available': a.available,
        },
    ]);
    await settings.save(
      AppSetting(
        key: SettingKeys.lowStockActiveJson,
        value: payload,
        updatedAt: clock.now(),
      ),
    );
  }
}
