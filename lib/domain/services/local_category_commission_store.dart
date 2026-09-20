import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

final class LocalCategoryCommissionStore {
  const LocalCategoryCommissionStore({
    required this.settings,
    required this.clock,
  });

  final SettingsRepository settings;
  final Clock clock;

  Future<Result<Map<String, int>>> _load() async {
    final found = await settings.find(SettingKeys.categoryCommissionBps);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final raw = (found as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) {
      return const Success(<String, int>{});
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const Success(<String, int>{});
      return Success({
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      });
    } catch (error) {
      return Failure(
        AppFailure(code: 'category_commission_corrupt', message: error.toString()),
      );
    }
  }

  Future<Result<int>> bpsFor(String categoryId) async {
    final loaded = await _load();
    if (loaded is Failure<Map<String, int>>) return Failure(loaded.error);
    return Success((loaded as Success<Map<String, int>>).value[categoryId] ?? 0);
  }

  Future<Result<void>> save({
    required String categoryId,
    required int commissionPercentBps,
  }) async {
    final loaded = await _load();
    if (loaded is Failure<Map<String, int>>) return Failure(loaded.error);
    final next = Map<String, int>.from((loaded as Success<Map<String, int>>).value);
    final clamped = commissionPercentBps < 0
        ? 0
        : (commissionPercentBps > 10000 ? 10000 : commissionPercentBps);
    if (clamped == 0) {
      next.remove(categoryId);
    } else {
      next[categoryId] = clamped;
    }
    return settings.save(
      AppSetting(
        key: SettingKeys.categoryCommissionBps,
        value: jsonEncode(next),
        updatedAt: clock.now(),
      ),
    );
  }
}
