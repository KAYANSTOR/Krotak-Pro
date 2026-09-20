import 'dart:convert';

import '../../core/app_brand.dart';
import '../../core/clock.dart';
import '../../core/result.dart';
import '../device_verification_gate.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

final class DeviceGateEvidence {
  const DeviceGateEvidence({
    required this.status,
    this.note,
    this.metrics = const {},
    this.recordedAt,
  });

  final DeviceVerificationStatus status;
  final String? note;
  final Map<String, num> metrics;
  final DateTime? recordedAt;

  bool get hasOperatorNote => note != null && note!.trim().isNotEmpty;
}

final class DeviceVerificationSnapshot {
  const DeviceVerificationSnapshot({
    this.gates = const {},
    Map<String, DeviceVerificationStatus>? statuses,
  }) : _legacyStatuses = statuses;

  final Map<String, Object> gates;
  final Map<String, DeviceVerificationStatus>? _legacyStatuses;

  DeviceVerificationStatus of(String id) {
    final legacy = _legacyStatuses?[id];
    if (legacy != null) return legacy;
    final raw = gates[id];
    if (raw is DeviceVerificationStatus) return raw;
    if (raw is DeviceGateEvidence) return raw.status;
    return DeviceVerificationStatus.pending;
  }

  DeviceGateEvidence evidenceOf(String id) {
    final raw = gates[id];
    if (raw is DeviceGateEvidence) return raw;
    if (raw is DeviceVerificationStatus) {
      return DeviceGateEvidence(status: raw);
    }
    return const DeviceGateEvidence(status: DeviceVerificationStatus.pending);
  }

  Map<String, DeviceVerificationStatus> get statuses => {
        for (final item in DeviceVerificationCatalog.items) item.id: of(item.id),
      };

  int get passedCount => DeviceVerificationCatalog.items
      .where((item) => of(item.id) == DeviceVerificationStatus.passed)
      .length;

  int get total => DeviceVerificationCatalog.items.length;

  bool get allPassed => DeviceVerificationCatalog.items
      .every((item) => of(item.id) == DeviceVerificationStatus.passed);

  bool get measurementGatesHaveEvidence {
    for (final id in DeviceVerificationCatalog.measurementGateIds) {
      if (of(id) != DeviceVerificationStatus.passed) continue;
      if (!evidenceOf(id).hasOperatorNote) return false;
    }
    return true;
  }

  /// Release is software-ready only when every gate passed and measurement notes exist.
  bool get readyForRelease => allPassed && measurementGatesHaveEvidence;
}

final class LocalDeviceVerificationService {
  LocalDeviceVerificationService({
    required SettingsRepository settings,
    required Clock clock,
  })  : _settings = settings,
        _clock = clock;

  final SettingsRepository _settings;
  final Clock _clock;

  static const _measurementRequiredNote =
      'قياس الجهاز إلزامي لهذه البوابة: أدخل ملاحظة المشغّل قبل التأكيد.';

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
    String? note,
    Map<String, num> metrics = const {},
  }) async {
    if (DeviceVerificationCatalog.byId(gateId) == null) {
      return const Failure(
        AppFailure(code: 'unknown_verification_gate', message: 'بوابة غير معروفة'),
      );
    }
    if (status == DeviceVerificationStatus.passed &&
        DeviceVerificationCatalog.measurementGateIds.contains(gateId) &&
        (note == null || note.trim().isEmpty)) {
      return const Failure(
        AppFailure(code: 'measurement_evidence_required', message: _measurementRequiredNote),
      );
    }

    final current = await load();
    if (current is Failure<DeviceVerificationSnapshot>) return current;
    final snap = (current as Success<DeviceVerificationSnapshot>).value;
    final next = Map<String, DeviceGateEvidence>.from({
      for (final item in DeviceVerificationCatalog.items) item.id: snap.evidenceOf(item.id),
    });
    next[gateId] = DeviceGateEvidence(
      status: status,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      metrics: metrics,
      recordedAt: _clock.now(),
    );
    return _persist(next);
  }

  Future<Result<DeviceVerificationSnapshot>> recordImportMeasurement({
    required int acceptedRows,
    required int rejectedRows,
    required int durationMs,
    String? note,
  }) {
    return mark(
      gateId: 'bulk_import',
      status: DeviceVerificationStatus.passed,
      note: note ?? 'استيراد دفعة: مقبول $acceptedRows / مرفوض $rejectedRows',
      metrics: {
        'acceptedRows': acceptedRows,
        'rejectedRows': rejectedRows,
        'durationMs': durationMs,
      },
    );
  }

  Future<Result<DeviceVerificationSnapshot>> recordBroadcastMeasurement({
    required int recipients,
    required int sent,
    required int failed,
    required int durationMs,
    String? note,
  }) {
    return mark(
      gateId: 'broadcast_rate',
      status: DeviceVerificationStatus.passed,
      note: note ?? 'بث: $sent نجح / $failed فشل من $recipients',
      metrics: {
        'recipients': recipients,
        'sent': sent,
        'failed': failed,
        'durationMs': durationMs,
      },
    );
  }

  Map<String, Object?> exportEvidencePack(DeviceVerificationSnapshot snap) {
    return {
      'phase': 19,
      'matchingPhase': 11,
      'appVersion': '${AppBrand.version}+${AppBrand.buildNumber}',
      'schema': 'net.device_verification.v1',
      'exportedAt': _clock.now().toIso8601String(),
      'passedCount': snap.passedCount,
      'total': snap.total,
      'allPassed': snap.allPassed,
      'measurementGatesHaveEvidence': snap.measurementGatesHaveEvidence,
      'readyForRelease': snap.readyForRelease,
      'gates': {
        for (final item in DeviceVerificationCatalog.items)
          item.id: {
            'title': item.title,
            'phaseRef': item.phaseRef,
            'status': snap.of(item.id).name,
            'note': snap.evidenceOf(item.id).note,
            'metrics': snap.evidenceOf(item.id).metrics,
            'recordedAt': snap.evidenceOf(item.id).recordedAt?.toIso8601String(),
          },
      },
    };
  }

  Future<Result<DeviceVerificationSnapshot>> _persist(
    Map<String, DeviceGateEvidence> gates,
  ) async {
    final encoded = jsonEncode({
      for (final e in gates.entries)
        e.key: {
          'status': e.value.status.name,
          if (e.value.note != null) 'note': e.value.note,
          if (e.value.metrics.isNotEmpty) 'metrics': e.value.metrics,
          if (e.value.recordedAt != null) 'recordedAt': e.value.recordedAt!.toIso8601String(),
        },
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
    return Success(DeviceVerificationSnapshot(gates: gates));
  }

  DeviceVerificationSnapshot _decode(String? raw) {
    final map = <String, DeviceGateEvidence>{};
    if (raw == null || raw.trim().isEmpty) {
      return const DeviceVerificationSnapshot(gates: {});
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is String) {
            map[key] = DeviceGateEvidence(status: _parseStatus(value));
          } else if (value is Map) {
            final metricsRaw = value['metrics'];
            final metrics = <String, num>{};
            if (metricsRaw is Map) {
              for (final m in metricsRaw.entries) {
                final n = m.value;
                if (n is num) metrics[m.key.toString()] = n;
              }
            }
            DateTime? recordedAt;
            final at = value['recordedAt']?.toString();
            if (at != null && at.isNotEmpty) {
              recordedAt = DateTime.tryParse(at);
            }
            map[key] = DeviceGateEvidence(
              status: _parseStatus(value['status']?.toString() ?? ''),
              note: value['note']?.toString(),
              metrics: metrics,
              recordedAt: recordedAt,
            );
          }
        }
      }
    } catch (_) {
      // Treat corrupt payload as empty pending snapshot.
    }
    return DeviceVerificationSnapshot(gates: map);
  }

  DeviceVerificationStatus _parseStatus(String name) {
    return DeviceVerificationStatus.values.firstWhere(
      (v) => v.name == name,
      orElse: () => DeviceVerificationStatus.pending,
    );
  }
}
