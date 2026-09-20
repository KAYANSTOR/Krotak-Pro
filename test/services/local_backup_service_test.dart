import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_backup_service.dart';

final class _MemSettings implements SettingsRepository {
  final map = <String, AppSetting>{};

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(map[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    map[setting.key] = setting;
    return const Success(null);
  }
}

final class _Ids implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) => '$prefix-${++n}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 17, 18, 0);
}

void main() {
  late Directory dir;
  late _MemSettings settings;
  late LocalBackupService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kartak-backup-');
    settings = _MemSettings();
    await settings.save(
      AppSetting(
        key: SettingKeys.networkName,
        value: 'NET-TEST',
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
    service = LocalBackupService(
      settings: settings,
      clock: _Clock(),
      ids: _Ids(),
      backupDirectory: dir,
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('rejects short password', () async {
    final r = await service.createBackup(password: '12');
    expect(r, isA<Failure<File>>());
    expect((r as Failure).error.code, 'backup_password_too_short');
  });

  test('encrypt round-trip restores settings', () async {
    final created = await service.createBackup(password: 'secret-pass', label: 't1');
    expect(created, isA<Success<File>>());
    final file = (created as Success<File>).value;
    expect(file.path.endsWith('.krt'), isTrue);
    expect(file.path.contains('znet'), isFalse);

    settings.map.clear();
    final restored = await service.restoreFromFile(file, password: 'secret-pass');
    expect(restored, isA<Success>());
    expect((restored as Success).value.settingsCount, greaterThan(0));
    expect(settings.map[SettingKeys.networkName]?.value, 'NET-TEST');
  });

  test('wrong password fails authentication', () async {
    final created = await service.createBackup(password: 'secret-pass');
    final file = (created as Success<File>).value;
    final restored = await service.restoreFromFile(file, password: 'wrong-pass');
    expect(restored, isA<Failure>());
    expect((restored as Failure).error.code, 'backup_wrong_password');
  });
}
