import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

final class LocalBackupService {
  const LocalBackupService({
    required this.settings,
    required this.clock,
    required this.ids,
    required this.backupDirectory,
  });

  final SettingsRepository settings;
  final Clock clock;
  final IdGenerator ids;
  final Directory backupDirectory;

  Future<Result<File>> createBackup({String? label}) async {
    try {
      if (!await backupDirectory.exists()) {
        await backupDirectory.create(recursive: true);
      }

      final keys = [
        SettingKeys.defaultCurrency,
        SettingKeys.reservationMinutes,
      ];
      final map = <String, String>{};
      for (final key in keys) {
        final result = await settings.find(key);
        if (result is Success<AppSetting?> && result.value != null) {
          map[key] = result.value!.value;
        }
      }

      final payload = {
        'id': ids.next('backup'),
        'label': label ?? 'manual',
        'createdAt': clock.now().toIso8601String(),
        'settings': map,
      };

      final fileName =
          'net-backup-${clock.now().millisecondsSinceEpoch}.json';
      final file = File(p.join(backupDirectory.path, fileName));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      return Success(file);
    } catch (e) {
      return Failure(
        AppFailure(code: 'backup_failed', message: e.toString()),
      );
    }
  }

  Future<Result<void>> restoreFromFile(File file) async {
    try {
      if (!await file.exists()) {
        return const Failure(
          AppFailure(code: 'backup_not_found', message: 'Backup file missing'),
        );
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final settingsMap =
          Map<String, dynamic>.from(decoded['settings'] as Map? ?? {});

      for (final entry in settingsMap.entries) {
        final save = await settings.save(
          AppSetting(
            key: entry.key,
            value: entry.value.toString(),
            updatedAt: clock.now(),
          ),
        );
        if (save is Failure<void>) return Failure(save.error);
      }
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure(code: 'restore_failed', message: e.toString()),
      );
    }
  }

  Future<Result<List<File>>> listBackups() async {
    try {
      if (!await backupDirectory.exists()) return const Success([]);
      final files = backupDirectory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return Success(files);
    } catch (e) {
      return Failure(
        AppFailure(code: 'list_backups_failed', message: e.toString()),
      );
    }
  }
}
