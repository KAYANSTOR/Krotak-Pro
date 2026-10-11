// تشخيص مؤقّت (سيُحذف بعد المعالجة) — لتحديد لماذا لا يكتمل
// `createBackup` داخل اختبار الواجهة (fake-async).
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/domain/entities/setting.dart';

/// ينتظر أكتمال [pending] داخل fake-async دون التعليق: حلقة محدودة من
/// runAsync (زمن حقيقي) + pump (يقدّم المؤقّتات الوهمية).
Future<bool> pumpUntilDone(
  WidgetTester tester,
  bool Function() isDone, {
  int iterations = 60,
}) async {
  for (var i = 0; i < iterations; i++) {
    if (isDone()) return true;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 200));
  }
  return isDone();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe crypto only in fake zone', (tester) async {
    var done = false;
    final sw = Stopwatch()..start();
    Future<void> run() async {
      await Sha256().hash(Uint8List.fromList(<int>[1, 2, 3]));
      final pbkdf2 =
          Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 10000, bits: 256);
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(<int>[1, 2, 3, 4]),
        nonce: List<int>.filled(16, 7),
      );
      await key.extractBytes();
      final aes = AesGcm.with256bits();
      await aes.encrypt(<int>[9, 9, 9],
          secretKey: SecretKey(List<int>.filled(32, 5)));
      done = true;
    }

    run();
    final ok = await pumpUntilDone(tester, () => done);
    // ignore: avoid_print
    print('PROBE-CRYPTO: done=$ok elapsed=${sw.elapsedMilliseconds}ms');
  });

  testWidgets('probe createBackup completion', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    var done = false;
    Object? value;
    final sw = Stopwatch()..start();
    container.backupService.createBackup(password: 'secret-pass').then((v) {
      done = true;
      value = v;
    });
    final ok = await pumpUntilDone(tester, () => done);
    // ignore: avoid_print
    print('PROBE-BACKUP: done=$ok elapsed=${sw.elapsedMilliseconds}ms value=${value.runtimeType}');
  });

  testWidgets('probe drift find + file write', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    var done = false;
    final sw = Stopwatch()..start();
    Future<void> run() async {
      await container.settings.find(SettingKeys.networkName);
      final f = File('test-backups/probe.txt');
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsString('hello', flush: true);
      done = true;
    }

    run();
    final ok = await pumpUntilDone(tester, () => done);
    // ignore: avoid_print
    print('PROBE-DRIFT: done=$ok elapsed=${sw.elapsedMilliseconds}ms');
  });
}
