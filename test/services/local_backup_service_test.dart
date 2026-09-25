import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

Uint8List _fakeSqlite({String marker = 'LIVE'}) {
  final bytes = Uint8List(128);
  final header = utf8.encode('SQLite format 3');
  bytes.setRange(0, header.length, header);
  bytes[header.length] = 0;
  final mark = utf8.encode(marker);
  bytes.setRange(20, 20 + mark.length, mark);
  return bytes;
}

void main() {
  late Directory dir;
  late _MemSettings settings;
  late File dbFile;
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
    dbFile = File('${dir.path}/net.sqlite');
    await dbFile.writeAsBytes(_fakeSqlite());
    service = LocalBackupService(
      settings: settings,
      clock: _Clock(),
      ids: _Ids(),
      backupDirectory: dir,
      databaseFile: dbFile,
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

  test('embedded sqlite is restored and live file kept as pre-restore', () async {
    final created = await service.createBackup(password: 'secret-pass');
    final file = (created as Success<File>).value;

    await dbFile.writeAsBytes(_fakeSqlite(marker: 'NEW'));
    final restored = await service.restoreFromFile(file, password: 'secret-pass');
    expect(restored, isA<Success<BackupRestoreReport>>());
    expect((restored as Success<BackupRestoreReport>).value.databaseRestored, isTrue);
    final live = await dbFile.readAsBytes();
    expect(utf8.decode(live.sublist(20, 24)), 'LIVE');
    final safety = File('${dbFile.path}.pre-restore');
    expect(await safety.exists(), isTrue);
    expect(utf8.decode((await safety.readAsBytes()).sublist(20, 23)), 'NEW');
  });

  test('invalid sqlite payload is rejected and live db is untouched', () async {
    final created = await service.createBackup(password: 'secret-pass');
    final file = (created as Success<File>).value;

    // Overwrite the live file then attempt restore of a forged envelope that
    // decrypts via the public API path: inject junk via a second service without
    // a valid header by writing junk as current db then backing it up.
    final junkDb = File('${dir.path}/junk.sqlite');
    await junkDb.writeAsBytes(utf8.encode('not a database payload...........'));
    final junkService = LocalBackupService(
      settings: settings,
      clock: _Clock(),
      ids: _Ids(),
      backupDirectory: dir,
      databaseFile: junkDb,
    );
    final junkBackup = await junkService.createBackup(password: 'secret-pass');
    final junkFile = (junkBackup as Success<File>).value;

    final before = await dbFile.readAsBytes();
    final restored = await service.restoreFromFile(junkFile, password: 'secret-pass');
    expect(restored, isA<Failure>());
    expect((restored as Failure).error.code, 'backup_database_invalid');
    expect(await dbFile.readAsBytes(), before);
  });

  test('license settings keys are not written back', () async {
    await settings.save(
      AppSetting(
        key: 'license_token',
        value: 'should-not-restore',
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
    // snapshotKeys does not include license_token; extra key only appears if
    // present in payload. Simulate via restore of settings-only JSON.
    final raw = File('${dir.path}/plain.json');
    await raw.writeAsString(
      jsonEncode({
        'settings': {
          SettingKeys.networkName: 'FROM-BACKUP',
          'license_secret': 'LEAK',
        },
      }),
    );
    settings.map.clear();
    final restored = await service.restoreFromFile(raw);
    expect(restored, isA<Success>());
    expect(settings.map[SettingKeys.networkName]?.value, 'FROM-BACKUP');
    expect(settings.map.containsKey('license_secret'), isFalse);
  });

  test('reapplyLicenseRows runs after a valid database restore', () async {
    final created = await service.createBackup(password: 'secret-pass');
    final file = (created as Success<File>).value;
    var applied = 0;
    final restored = await service.restoreFromFile(
      file,
      password: 'secret-pass',
      preserveLicenseRows: [
        {'id': 'lic-1'},
      ],
      reapplyLicenseRows: (rows) async {
        applied = rows.length;
      },
    );
    expect(restored, isA<Success<BackupRestoreReport>>());
    expect(applied, 1);
    expect(
      (restored as Success<BackupRestoreReport>).value.licenseRowsPreserved,
      1,
    );
  });
}
