import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' show AppDatabase;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';

import '../helpers/in_memory_repositories.dart';

final class _MemWallets implements WalletRepository {
  final map = <String, Wallet>{};

  @override
  Future<Result<Wallet?>> findById(String id) async => Success(map[id]);

  @override
  Future<Result<List<Wallet>>> listAll() async =>
      Success(map.values.toList(growable: false));

  @override
  Future<Result<void>> save(Wallet wallet) async {
    map[wallet.id] = wallet;
    return const Success(null);
  }
}

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

void main() {
  final now = DateTime.utc(2026, 10, 4, 9);

  group('LocalWalletCatalogService (in-memory)', () {
    late _MemWallets wallets;
    late _MemSettings settings;
    late InMemoryAuditLogRepository audit;
    late LocalWalletCatalogService catalog;

    setUp(() {
      wallets = _MemWallets();
      settings = _MemSettings();
      audit = InMemoryAuditLogRepository();
      catalog = LocalWalletCatalogService(
        wallets: wallets,
        auditLogs: audit,
        settings: settings,
        clock: FixedClock(now),
        ids: SequentialIdGenerator(),
      );
    });

    Future<Wallet> create(
      String name, {
      String? senderId,
      WalletSourceMode mode = WalletSourceMode.sms,
      String? packageName,
    }) async {
      final r = await catalog.saveWallet(
        name: name,
        senderId: senderId,
        sourceMode: mode,
        packageName: packageName,
      );
      return (r as Success<Wallet>).value;
    }

    group('saveWallet', () {
      test('trims fields, starts active, stamps the clock and audits once', () async {
        final w = await create(
          '  جيب  ',
          senderId: '  JAIB ',
          mode: WalletSourceMode.notification,
          packageName: ' com.ahd.jaib ',
        );
        expect(w.name, 'جيب');
        expect(w.senderId, 'JAIB');
        expect(w.packageName, 'com.ahd.jaib');
        expect(w.sourceMode, WalletSourceMode.notification);
        expect(w.status, WalletStatus.active);
        expect(w.createdAt, now);
        expect(wallets.map[w.id], isNotNull);

        final logs = audit.logs.where((l) => l.entityType == 'wallet').toList();
        expect(logs.length, 1);
        expect(logs.single.entityId, w.id);
        expect(logs.single.action, 'saved');
      });

      test('blank sender and package are stored as null, never as empty text', () async {
        final w = await create('محفظة', senderId: '   ', packageName: '');
        expect(w.senderId, isNull);
        expect(w.packageName, isNull);
      });

      for (final bad in ['', '   ', '\n\t ']) {
        test('rejects a blank name (${bad.codeUnits}) and persists nothing', () async {
          final r = await catalog.saveWallet(name: bad);
          expect(r, isA<Failure<Wallet>>());
          expect((r as Failure<Wallet>).error.code, 'invalid_wallet_name');
          expect(wallets.map, isEmpty);
          expect(audit.logs, isEmpty);
          expect(settings.map.containsKey(SettingKeys.walletExtras), isFalse);
        });
      }

      test('every wallet gets a distinct id', () async {
        final a = await create('أ');
        final b = await create('ب');
        final c = await create('ج');
        expect({a.id, b.id, c.id}.length, 3);
      });

      test('extras are persisted as JSON keyed by wallet id', () async {
        final w = await create(
          'جوالي',
          senderId: 'JAWALI',
          mode: WalletSourceMode.sms,
          packageName: 'com.wecash.jawali',
        );
        final raw = settings.map[SettingKeys.walletExtras]!.value;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final extra = decoded[w.id] as Map<String, dynamic>;
        expect(extra['senderId'], 'JAWALI');
        expect(extra['sourceMode'], 'sms');
        expect(extra['packageName'], 'com.wecash.jawali');
      });
    });

    group('listEnriched', () {
      test('extras override the repository values', () async {
        wallets.map['w1'] = Wallet(
          id: 'w1',
          name: 'قديم',
          status: WalletStatus.active,
          createdAt: now,
          senderId: 'OLD',
        );
        settings.map[SettingKeys.walletExtras] = AppSetting(
          key: SettingKeys.walletExtras,
          value: jsonEncode({
            'w1': {'senderId': 'NEW', 'sourceMode': 'notification', 'packageName': 'pkg.a'},
          }),
          updatedAt: now,
        );
        final r = await catalog.listEnriched();
        final w = (r as Success<List<Wallet>>).value.single;
        expect(w.senderId, 'NEW');
        expect(w.sourceMode, WalletSourceMode.notification);
        expect(w.packageName, 'pkg.a');
      });

      test('unknown source mode degrades to sms', () async {
        wallets.map['w1'] = Wallet(id: 'w1', name: 'م', status: WalletStatus.active, createdAt: now);
        settings.map[SettingKeys.walletExtras] = AppSetting(
          key: SettingKeys.walletExtras,
          value: jsonEncode({'w1': {'sourceMode': 'carrier-pigeon'}}),
          updatedAt: now,
        );
        final w = ((await catalog.listEnriched()) as Success<List<Wallet>>).value.single;
        expect(w.sourceMode, WalletSourceMode.sms);
      });

      for (final corrupt in ['{not json', '[]', '"text"', '42', '']) {
        test('corrupt extras ($corrupt) never crash and keep the base wallet', () async {
          wallets.map['w1'] = Wallet(
            id: 'w1',
            name: 'م',
            status: WalletStatus.active,
            createdAt: now,
            senderId: 'BASE',
          );
          settings.map[SettingKeys.walletExtras] =
              AppSetting(key: SettingKeys.walletExtras, value: corrupt, updatedAt: now);
          final r = await catalog.listEnriched();
          expect(r, isA<Success<List<Wallet>>>());
          expect((r as Success<List<Wallet>>).value.single.senderId, 'BASE');
        });
      }

      test('a wallet without extras is returned untouched', () async {
        wallets.map['w1'] = Wallet(id: 'w1', name: 'م', status: WalletStatus.suspended, createdAt: now);
        final w = ((await catalog.listEnriched()) as Success<List<Wallet>>).value.single;
        expect(w.status, WalletStatus.suspended);
        expect(w.sourceMode, WalletSourceMode.sms);
        expect(w.senderId, isNull);
      });
    });

    group('updateWallet', () {
      test('fails for an unknown id without writing or auditing', () async {
        final r = await catalog.updateWallet(id: 'ghost', name: 'x', status: WalletStatus.active);
        expect((r as Failure<Wallet>).error.code, 'wallet_not_found');
        expect(wallets.map, isEmpty);
        expect(audit.logs, isEmpty);
      });

      test('rejects a blank name and leaves the stored wallet unchanged', () async {
        final w = await create('جيب', senderId: 'JAIB');
        final before = audit.logs.length;
        final r = await catalog.updateWallet(id: w.id, name: '  ', status: WalletStatus.suspended);
        expect((r as Failure<Wallet>).error.code, 'invalid_wallet_name');
        expect(wallets.map[w.id]!.name, 'جيب');
        expect(wallets.map[w.id]!.status, WalletStatus.active);
        expect(audit.logs.length, before);
      });

      test('keeps id and createdAt, trims the name', () async {
        final w = await create('جيب');
        final r = await catalog.updateWallet(id: w.id, name: '  جيب كاش  ', status: WalletStatus.active);
        final u = (r as Success<Wallet>).value;
        expect(u.id, w.id);
        expect(u.createdAt, w.createdAt);
        expect(u.name, 'جيب كاش');
      });

      test('walks through every status and audits each change with its payload', () async {
        final w = await create('جيب');
        for (final s in [
          WalletStatus.suspended,
          WalletStatus.archived,
          WalletStatus.active,
        ]) {
          final r = await catalog.updateWallet(id: w.id, name: w.name, status: s);
          expect((r as Success<Wallet>).value.status, s);
          expect(wallets.map[w.id]!.status, s);
        }
        final changes = audit.logs.where((l) => l.action == 'status_changed').toList();
        expect(changes.length, 3);
        expect(
          changes.map((l) => (jsonDecode(l.payloadJson!) as Map)['status']).toList(),
          ['suspended', 'archived', 'active'],
        );
      });

      test('omitted sender, mode and package keep their previous values', () async {
        final w = await create(
          'جيب',
          senderId: 'JAIB',
          mode: WalletSourceMode.notification,
          packageName: 'com.ahd.jaib',
        );
        final u = ((await catalog.updateWallet(
          id: w.id,
          name: 'جيب',
          status: WalletStatus.suspended,
        )) as Success<Wallet>)
            .value;
        expect(u.senderId, 'JAIB');
        expect(u.sourceMode, WalletSourceMode.notification);
        expect(u.packageName, 'com.ahd.jaib');
      });

      test('explicit values replace the previous ones and are trimmed', () async {
        final w = await create('جيب', senderId: 'JAIB', packageName: 'old.pkg');
        final u = ((await catalog.updateWallet(
          id: w.id,
          name: 'جيب',
          status: WalletStatus.active,
          senderId: '  NEWSENDER ',
          sourceMode: WalletSourceMode.notification,
          packageName: ' new.pkg ',
        )) as Success<Wallet>)
            .value;
        expect(u.senderId, 'NEWSENDER');
        expect(u.packageName, 'new.pkg');
        expect(u.sourceMode, WalletSourceMode.notification);
        final listed = ((await catalog.listEnriched()) as Success<List<Wallet>>).value.single;
        expect(listed.senderId, 'NEWSENDER');
        expect(listed.packageName, 'new.pkg');
      });

      test('a blank sender clears it (null), it is never stored as empty or spaces', () async {
        final w = await create('جيب', senderId: 'JAIB');
        final u = ((await catalog.updateWallet(
          id: w.id,
          name: 'جيب',
          status: WalletStatus.active,
          senderId: '   ',
        )) as Success<Wallet>)
            .value;
        expect(u.senderId, isNull);
        final listed = ((await catalog.listEnriched()) as Success<List<Wallet>>).value.single;
        expect(listed.senderId, isNull);
      });

      test('switching to sms mode without a package clears the package', () async {
        final w = await create(
          'جيب',
          senderId: 'JAIB',
          mode: WalletSourceMode.notification,
          packageName: 'com.ahd.jaib',
        );
        final u = ((await catalog.updateWallet(
          id: w.id,
          name: 'جيب',
          status: WalletStatus.active,
          sourceMode: WalletSourceMode.sms,
          packageName: '',
        )) as Success<Wallet>)
            .value;
        expect(u.sourceMode, WalletSourceMode.sms);
        expect(u.packageName, isNull);
      });
    });

    group('ensureDefaultWallets', () {
      Future<List<Wallet>> all() async =>
          ((await catalog.listEnriched()) as Success<List<Wallet>>).value;

      test('seeds exactly the four standard wallets with the right transport', () async {
        expect(await catalog.ensureDefaultWallets(), isA<Success<void>>());
        final byName = {for (final w in await all()) w.name: w};
        expect(byName.keys.toSet(), {'جيب', 'جوالي', 'ون كاش', 'فلوسك'});

        expect(byName['جيب']!.sourceMode, WalletSourceMode.notification);
        expect(byName['جيب']!.packageName, 'com.ahd.jaib');
        expect(byName['جيب']!.senderId, 'JAIB');
        expect(byName['جوالي']!.sourceMode, WalletSourceMode.sms);
        expect(byName['جوالي']!.senderId, 'JAWALI');
        expect(byName['ون كاش']!.senderId, 'ONE CASH');
        expect(byName['فلوسك']!.senderId, 'FLOOSAK');
        expect(byName.values.every((w) => w.status == WalletStatus.active), isTrue);
        expect(settings.map[SettingKeys.defaultWalletsSeeded]!.value, 'true');
      });

      test('is idempotent: repeated boots never duplicate wallets', () async {
        for (var i = 0; i < 4; i++) {
          await catalog.ensureDefaultWallets();
        }
        expect((await all()).length, 4);
      });

      test('matches an existing wallet by name even when the stored name is padded', () async {
        wallets.map['padded'] = Wallet(
          id: 'padded',
          name: '  جيب  ',
          status: WalletStatus.active,
          createdAt: now,
          senderId: 'CUSTOM',
        );
        await catalog.ensureDefaultWallets();
        final names = (await all()).map((w) => w.name.trim()).toList();
        expect(names.where((n) => n == 'جيب').length, 1);
        expect(names.length, 4);
      });

      test('never overwrites operator-edited sender, mode or package', () async {
        await catalog.ensureDefaultWallets();
        final jaib = (await all()).firstWhere((w) => w.name == 'جيب');
        await catalog.updateWallet(
          id: jaib.id,
          name: 'جيب',
          status: WalletStatus.active,
          senderId: 'MYJAIB',
          sourceMode: WalletSourceMode.sms,
          packageName: '',
        );
        await catalog.ensureDefaultWallets();
        final after = (await all()).firstWhere((w) => w.id == jaib.id);
        expect(after.senderId, 'MYJAIB');
        expect(after.sourceMode, WalletSourceMode.sms);
        expect(after.packageName, isNull);
      });

      test('does not resurrect or reactivate a suspended or archived default', () async {
        await catalog.ensureDefaultWallets();
        final list = await all();
        final jaib = list.firstWhere((w) => w.name == 'جيب');
        final floosak = list.firstWhere((w) => w.name == 'فلوسك');
        await catalog.updateWallet(id: jaib.id, name: 'جيب', status: WalletStatus.suspended);
        await catalog.updateWallet(id: floosak.id, name: 'فلوسك', status: WalletStatus.archived);
        await catalog.ensureDefaultWallets();
        final after = {for (final w in await all()) w.id: w};
        expect(after.length, 4);
        expect(after[jaib.id]!.status, WalletStatus.suspended);
        expect(after[floosak.id]!.status, WalletStatus.archived);
      });

      test('renaming a default wallet does not seed a duplicate on the next boot', () async {
        await catalog.ensureDefaultWallets();
        final jaib = (await all()).firstWhere((w) => w.name == 'جيب');
        await catalog.updateWallet(id: jaib.id, name: 'محفظتي الخاصة', status: WalletStatus.active);
        await catalog.ensureDefaultWallets();
        final list = await all();
        expect(list.length, 4);
        expect(list.where((w) => w.senderId == 'JAIB').length, 1);
        expect(list.any((w) => w.name == 'جيب'), isFalse);
      });

      test('a pre-existing default without extras gets its transport filled in', () async {
        wallets.map['legacy'] = Wallet(
          id: 'legacy',
          name: 'جوالي',
          status: WalletStatus.active,
          createdAt: now,
        );
        await catalog.ensureDefaultWallets();
        final legacy = (await all()).firstWhere((w) => w.id == 'legacy');
        expect(legacy.senderId, 'JAWALI');
        expect(legacy.packageName, 'com.wecash.jawali');
      });
    });
  });

  group('wallet persistence on the real database', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => database.close());

    LocalWalletCatalogService buildCatalog() => LocalWalletCatalogService(
          wallets: LocalWalletRepository(database),
          auditLogs: LocalAuditLogRepository(database),
          settings: LocalSettingsRepository(database),
          clock: FixedClock(now),
          ids: SequentialIdGenerator(),
        );

    test('wallets and their transport survive a service restart', () async {
      final first = buildCatalog();
      await first.ensureDefaultWallets();
      final second = buildCatalog();
      final list = ((await second.listEnriched()) as Success<List<Wallet>>).value;
      expect(list.length, 4);
      final jaib = list.firstWhere((w) => w.name == 'جيب');
      expect(jaib.sourceMode, WalletSourceMode.notification);
      expect(jaib.packageName, 'com.ahd.jaib');
    });

    test('seeding twice on the real database stays at four wallets', () async {
      final catalog = buildCatalog();
      await catalog.ensureDefaultWallets();
      await catalog.ensureDefaultWallets();
      final list = ((await catalog.listEnriched()) as Success<List<Wallet>>).value;
      expect(list.length, 4);
    });

    test('status changes persist and are audited in the database', () async {
      final catalog = buildCatalog();
      final w = ((await catalog.saveWallet(name: 'تجريبية', senderId: 'TEST')) as Success<Wallet>).value;
      await catalog.updateWallet(id: w.id, name: 'تجريبية', status: WalletStatus.suspended);

      final found = await LocalWalletRepository(database).findById(w.id);
      expect((found as Success<Wallet?>).value!.status, WalletStatus.suspended);
      final logs = await LocalAuditLogRepository(database).findByEntity('wallet', w.id);
      expect(
        (logs as Success<List<AuditLog>>).value.map((l) => l.action).toList(),
        containsAll(<String>['saved', 'status_changed']),
      );
    });

    test('a blank sender update is cleared on the real database as well', () async {
      final catalog = buildCatalog();
      final w = ((await catalog.saveWallet(name: 'م', senderId: 'ABC')) as Success<Wallet>).value;
      await catalog.updateWallet(id: w.id, name: 'م', status: WalletStatus.active, senderId: ' ');
      final listed = ((await catalog.listEnriched()) as Success<List<Wallet>>).value.single;
      expect(listed.senderId, isNull);
    });

    test('corrupt stored extras do not break wallet listing', () async {
      final repo = LocalWalletRepository(database);
      await repo.save(
        Wallet(id: 'w1', name: 'م', status: WalletStatus.active, createdAt: now, senderId: 'X'),
      );
      await LocalSettingsRepository(database).save(
        AppSetting(key: SettingKeys.walletExtras, value: '{broken', updatedAt: now),
      );
      final r = await repo.listAll();
      expect(r, isA<Success<List<Wallet>>>());
      expect((r as Success<List<Wallet>>).value.single.sourceMode, WalletSourceMode.sms);
    });

    test('wallets are listed ordered by name', () async {
      final repo = LocalWalletRepository(database);
      for (final n in ['ج', 'أ', 'ب']) {
        await repo.save(Wallet(id: 'id-$n', name: n, status: WalletStatus.active, createdAt: now));
      }
      final names = ((await repo.listAll()) as Success<List<Wallet>>).value.map((w) => w.name).toList();
      final sorted = [...names]..sort();
      expect(names, sorted);
    });
  });
}
