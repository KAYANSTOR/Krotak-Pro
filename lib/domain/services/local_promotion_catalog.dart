import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/promotion.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// كتالوج العروض الترويجية — قراءة/كتابة عبر Settings (offline-first).
final class LocalPromotionCatalog {
  const LocalPromotionCatalog({
    required this.settings,
    required this.clock,
    required this.ids,
  });

  final SettingsRepository settings;
  final Clock clock;
  final IdGenerator ids;

  Future<Result<List<Promotion>>> listAll() async {
    final found = await settings.find(SettingKeys.promotionsCatalog);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final raw = (found as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) {
      return const Success(<Promotion>[]);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const Success(<Promotion>[]);
      }
      final list = <Promotion>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          list.add(Promotion.fromJson(item));
        } else if (item is Map) {
          list.add(Promotion.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Success(list);
    } catch (e) {
      return Failure(
        AppFailure(code: 'promotions_parse_failed', message: e.toString()),
      );
    }
  }

  Future<Result<Promotion>> save(Promotion promotion) async {
    final listed = await listAll();
    if (listed is Failure<List<Promotion>>) return Failure(listed.error);
    final items = List<Promotion>.of((listed as Success<List<Promotion>>).value);
    final idx = items.indexWhere((p) => p.id == promotion.id);
    if (idx >= 0) {
      items[idx] = promotion;
    } else {
      items.insert(0, promotion);
    }
    final persisted = await _persist(items);
    if (persisted is Failure<void>) return Failure(persisted.error);
    return Success(promotion);
  }

  Future<Result<Promotion>> create({
    required String title,
    required int thresholdMinorUnits,
    required String rewardCategoryId,
    String currencyCode = 'YER',
    String? notes,
  }) {
    final name = title.trim();
    if (name.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_title', message: 'عنوان العرض مطلوب'),
        ),
      );
    }
    if (thresholdMinorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_threshold', message: 'عتبة التراكم يجب أن تكون موجبة'),
        ),
      );
    }
    if (rewardCategoryId.trim().isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_reward', message: 'اختر فئة مكافأة'),
        ),
      );
    }
    final promo = Promotion(
      id: ids.next('promo'),
      title: name,
      status: PromotionStatus.active,
      thresholdMinorUnits: thresholdMinorUnits,
      currencyCode: currencyCode,
      rewardCategoryId: rewardCategoryId.trim(),
      createdAt: clock.now(),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );
    return save(promo);
  }

  Future<Result<void>> setStatus(String id, PromotionStatus status) async {
    final listed = await listAll();
    if (listed is Failure<List<Promotion>>) return Failure(listed.error);
    final items = List<Promotion>.of((listed as Success<List<Promotion>>).value);
    final idx = items.indexWhere((p) => p.id == id);
    if (idx < 0) {
      return const Failure(
        AppFailure(code: 'promo_not_found', message: 'العرض غير موجود'),
      );
    }
    items[idx] = items[idx].copyWith(status: status);
    return _persist(items);
  }

  Future<Result<void>> delete(String id) async {
    final listed = await listAll();
    if (listed is Failure<List<Promotion>>) return Failure(listed.error);
    final items = List<Promotion>.of((listed as Success<List<Promotion>>).value)
      ..removeWhere((p) => p.id == id);
    return _persist(items);
  }

  Future<Result<void>> _persist(List<Promotion> items) async {
    final payload = jsonEncode(items.map((e) => e.toJson()).toList());
    return settings.save(
      AppSetting(
        key: SettingKeys.promotionsCatalog,
        value: payload,
        updatedAt: clock.now(),
      ),
    );
  }
}
