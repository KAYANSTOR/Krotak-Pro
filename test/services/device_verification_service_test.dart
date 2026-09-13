import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/device_verification_gate.dart';
import 'package:net_app/domain/services/local_device_verification_service.dart';

void main() {
  late AppDatabase database;
  late LocalSettingsRepository settings;
  late LocalDeviceVerificationService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    settings = LocalSettingsRepository(database);
    service = LocalDeviceVerificationService(
      settings: settings,
      clock: FixedClock(DateTime(2026, 9, 13)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('empty snapshot treats every gate as pending', () async {
    final loaded = await service.load();
    expect(loaded, isA<Success<DeviceVerificationSnapshot>>());
    final snap = (loaded as Success<DeviceVerificationSnapshot>).value;
    expect(snap.passedCount, 0);
    expect(snap.allPassed, isFalse);
    expect(snap.of('sms_send_receive'), DeviceVerificationStatus.pending);
  });

  test('mark persists and reloads', () async {
    final marked = await service.mark(
      gateId: 'salafni',
      status: DeviceVerificationStatus.passed,
    );
    expect(marked, isA<Success<DeviceVerificationSnapshot>>());
    expect(
      (marked as Success<DeviceVerificationSnapshot>).value.of('salafni'),
      DeviceVerificationStatus.passed,
    );

    final reloaded = await service.load();
    expect(
      (reloaded as Success<DeviceVerificationSnapshot>).value.of('salafni'),
      DeviceVerificationStatus.passed,
    );
  });

  test('unknown gate is rejected', () async {
    final result = await service.mark(
      gateId: 'not-a-gate',
      status: DeviceVerificationStatus.passed,
    );
    expect(result, isA<Failure<DeviceVerificationSnapshot>>());
    expect((result as Failure<DeviceVerificationSnapshot>).error.code, 'unknown_verification_gate');
  });
}
