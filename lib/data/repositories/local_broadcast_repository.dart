import 'dart:convert';

import '../../core/result.dart';
import '../../domain/entities/broadcast.dart';
import '../../domain/entities/setting.dart';
import '../../domain/repositories/repositories.dart';

const broadcastJobsSettingKey = 'broadcast_jobs';

final class LocalBroadcastRepository {
  const LocalBroadcastRepository({required this.settings});

  final SettingsRepository settings;

  Future<Result<List<BroadcastJob>>> listAll() async {
    final raw = await settings.find(broadcastJobsSettingKey);
    if (raw is Failure<AppSetting?>) return Failure(raw.error);
    final value = (raw as Success<AppSetting?>).value?.value;
    if (value == null || value.trim().isEmpty) return const Success([]);
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return const Success([]);
      final jobs = decoded['jobs'] as List<dynamic>? ?? const [];
      return Success(
        jobs
            .whereType<Map>()
            .map((row) => BroadcastJob.fromJson(Map<String, dynamic>.from(row)))
            .toList(),
      );
    } catch (error) {
      return Failure(AppFailure(code: 'broadcast_decode_failed', message: error.toString()));
    }
  }

  Future<Result<BroadcastJob?>> findById(String id) async {
    final all = await listAll();
    if (all is Failure<List<BroadcastJob>>) return Failure(all.error);
    for (final job in (all as Success<List<BroadcastJob>>).value) {
      if (job.id == id) return Success(job);
    }
    return const Success(null);
  }

  Future<Result<BroadcastJob?>> findByFingerprint(String fingerprint) async {
    final all = await listAll();
    if (all is Failure<List<BroadcastJob>>) return Failure(all.error);
    for (final job in (all as Success<List<BroadcastJob>>).value) {
      if (job.fingerprint == fingerprint) return Success(job);
    }
    return const Success(null);
  }

  Future<Result<void>> save(BroadcastJob job) async {
    final all = await listAll();
    if (all is Failure<List<BroadcastJob>>) return Failure(all.error);
    final jobs = [...(all as Success<List<BroadcastJob>>).value];
    final index = jobs.indexWhere((row) => row.id == job.id);
    if (index >= 0) {
      jobs[index] = job;
    } else {
      jobs.add(job);
    }
    final payload = jsonEncode({
      'jobs': jobs.map((row) => row.toJson()).toList(growable: false),
    });
    return settings.save(
      AppSetting(key: broadcastJobsSettingKey, value: payload, updatedAt: job.createdAt),
    );
  }
}
