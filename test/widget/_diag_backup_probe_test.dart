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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe crypto only in fake zone', (tester) async {
    final sw = Stopwatch()..start();
    // ignore: avoid_print
    print('CRYPTO: start');
    final hash = await Sha256().hash(Uint8List.fromList(<int>[1, 2, 3]));
    // ignore: avoid_print
    print('CRYPTO: sha256 done ${hash.bytes.length} in ${sw.elapsedMilliseconds}ms');
    final pbkdf2 =
        Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 10000, bits: 256);
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(<int>[1, 2, 3, 4]),
      nonce: List<int>.filled(16, 7),
    );
    final keyBytes = await key.extractBytes();
    // ignore: avoid_print
    print('CRYPTO: pbkdf2 done in ${sw.elapsedMilliseconds}ms key=${keyBytes.length}');
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      <int>[9, 9, 9],
      secretKey: SecretKey(List<int>.filled(32, 5)),
    );
    // ignore: avoid_print
    print('CRYPTO: aes done in ${sw.elapsedMilliseconds}ms ct=${box.cipherText.length}');
  });

  testWidgets('probe drift find + file write in fake zone', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    // ignore: avoid_print
    print('D1: start find');
    final r = await container.settings.find(SettingKeys.networkName);
    // ignore: avoid_print
    print('D1: find done ${r.runtimeType}');
    final f = File('test-backups/probe.txt');
    if (!await f.parent.exists()) {
      await f.parent.create(recursive: true);
    }
    await f.writeAsString('hello', flush: true);
    // ignore: avoid_print
    print('D1: write done');
  });

  testWidgets('probe createBackup driven by runAsync loop', (tester) async {
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
    for (var i = 0; i < 40 && !done; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    // ignore: avoid_print
    print('BACKUP-LOOP: done=$done after ${sw.elapsedMilliseconds}ms value=${value.runtimeType}');
    expect(done, isTrue, reason: 'createBackup لم يكتمل (loop)');
  });

  testWidgets('probe createBackup inside runAsync', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    final sw = Stopwatch()..start();
    Object? value;
    await tester.runAsync(() async {
      value = await container.backupService.createBackup(password: 'secret-pass');
    });
    // ignore: avoid_print
    print('BACKUP-RUNASYNC: done in ${sw.elapsedMilliseconds}ms value=${value.runtimeType}');
  });
}
