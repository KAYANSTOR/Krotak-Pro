import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide AppSetting;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/device_verification_gate.dart';
import 'package:net_app/domain/entities/setting.dart';
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
    expect(snap.readyForRelease, isFalse);
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

  test('bulk import passed requires operator note', () async {
    final result = await service.mark(
      gateId: 'bulk_import',
      status: DeviceVerificationStatus.passed,
    );
    expect(result, isA<Failure<DeviceVerificationSnapshot>>());
    expect(
      (result as Failure<DeviceVerificationSnapshot>).error.code,
      'measurement_evidence_required',
    );
  });

  test('recordImportMeasurement stores metrics and note', () async {
    final result = await service.recordImportMeasurement(
      acceptedRows: 80,
      rejectedRows: 2,
      durationMs: 1400,
    );
    expect(result, isA<Success<DeviceVerificationSnapshot>>());
    final snap = (result as Success<DeviceVerificationSnapshot>).value;
    expect(snap.of('bulk_import'), DeviceVerificationStatus.passed);
    expect(snap.evidenceOf('bulk_import').metrics['acceptedRows'], 80);
    expect(snap.evidenceOf('bulk_import').hasOperatorNote, isTrue);
    expect(snap.measurementGatesHaveEvidence, isTrue);
  });

  test('recordBroadcastMeasurement stores rate evidence', () async {
    final result = await service.recordBroadcastMeasurement(
      recipients: 12,
      sent: 11,
      failed: 1,
      durationMs: 9000,
    );
    expect(result, isA<Success<DeviceVerificationSnapshot>>());
    final snap = (result as Success<DeviceVerificationSnapshot>).value;
    expect(snap.of('broadcast_rate'), DeviceVerificationStatus.passed);
    expect(snap.evidenceOf('broadcast_rate').metrics['sent'], 11);
  });

  test('exportEvidencePack includes schema and gate rows', () async {
    await service.recordImportMeasurement(
      acceptedRows: 10,
      rejectedRows: 0,
      durationMs: 500,
    );
    final loaded = await service.load();
    final snap = (loaded as Success<DeviceVerificationSnapshot>).value;
    final pack = service.exportEvidencePack(snap);
    expect(pack['phase'], 19);
    expect(pack['schema'], 'net.device_verification.v1');
    expect(pack['readyForRelease'], isFalse);
    final gates = pack['gates'] as Map;
    expect(gates.containsKey('bulk_import'), isTrue);
    expect((gates['bulk_import'] as Map)['status'], 'passed');
  });

  test('legacy string payload still decodes', () async {
    await settings.save(
      AppSetting(
        key: DeviceVerificationCatalog.settingKey,
        value: '{"salafni":"passed"}',
        updatedAt: DateTime(2026, 9, 13),
      ),
    );
    final loaded = await service.load();
    expect(
      (loaded as Success<DeviceVerificationSnapshot>).value.of('salafni'),
      DeviceVerificationStatus.passed,
    );
  });
}
