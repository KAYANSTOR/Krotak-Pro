import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../device_verification_gate.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

final class DeviceVerificationSnapshot {
  const DeviceVerificationSnapshot({required this.statuses});

  final Map<String, DeviceVerificationStatus> statuses;

  DeviceVerificationStatus of(String id) =>
      statuses[id] ?? DeviceVerificationStatus.pending;

  int get passedCount => statuses.values
      .where((s) => s == DeviceVerificationStatus.passed)
      .length;

  int get total => DeviceVerificationCatalog.items.length;

  bool get allPassed =>
      DeviceVerificationCatalog.items.every((item) => of(item.id) == DeviceVerificationStatus.passed);
}

final class LocalDeviceVerificationService {
  LocalDeviceVerificationService({
    required SettingsRepository settings,
    required Clock clock,
  })  : _settings = settings,
        _clock = clock;

  final SettingsRepository _settings;
  final Clock _clock;

  Future<Result<DeviceVerificationSnapshot>> load() async {
    final result = await _settings.find(DeviceVerificationCatalog.settingKey);
    if (result is Failure<AppSetting?>) {
      return Failure(result.error);
    }
    final raw = (result as Success<AppSetting?>).value?.value;
    return Success(_decode(raw));
  }

  Future<Result<DeviceVerificationSnapshot>> mark({
    required String gateId,
    required DeviceVerificationStatus status,
  }) async {
    if (DeviceVerificationCatalog.byId(gateId) == null) {
      return const Failure(AppFailure(code: 'unknown_verification_gate', message: 'بوابة غير معروفة'));
    }
    final current = await load();
    if (current is Failure<DeviceVerificationSnapshot>) return current;
    final map = Map<String, DeviceVerificationStatus>.from(
      (current as Success<DeviceVerificationSnapshot>).value.statuses,
    );
    map[gateId] = status;
    final encoded = jsonEncode({
      for (final e in map.entries) e.key: e.value.name,
    });
    final saved = await _settings.save(
      AppSetting(
        key: DeviceVerificationCatalog.settingKey,
        value: encoded,
        updatedAt: _clock.now(),
      ),
    );
    if (saved is Failure<void>) {
      return Failure((saved as Failure).error);
    }
    return Success(DeviceVerificationSnapshot(statuses: map));
  }

  DeviceVerificationSnapshot _decode(String? raw) {
    final map = <String, DeviceVerificationStatus>{};
    if (raw == null || raw.trim().isEmpty) {
      return DeviceVerificationSnapshot(statuses: map);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final name = entry.value.toString();
          map[key] = DeviceVerificationStatus.values.firstWhere(
            (v) => v.name == name,
            orElse: () => DeviceVerificationStatus.pending,
          );
        }
      }
    } catch (_) {
      // Treat corrupt payload as empty pending snapshot.
    }
    return DeviceVerificationSnapshot(statuses: map);
  }
}
