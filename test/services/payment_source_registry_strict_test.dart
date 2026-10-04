import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_payment_source_registry.dart';

final class _Settings implements SettingsRepository {
  final map = <String, AppSetting>{};
  var saves = 0;

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(map[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    saves++;
    map[setting.key] = setting;
    return const Success(null);
  }
}

void main() {
  final at = DateTime.utc(2026, 10, 4, 11);
  late _Settings settings;
  late LocalPaymentSourceRegistry registry;

  setUp(() {
    settings = _Settings();
    registry = LocalPaymentSourceRegistry(settings: settings, clock: FixedClock(at));
  });

  void store(String raw) => settings.map[SettingKeys.notificationSources] =
      AppSetting(key: SettingKeys.notificationSources, value: raw, updatedAt: at);

  Future<List<PaymentSource>> list() async =>
      ((await registry.list()) as Success<List<PaymentSource>>).value;

  Wallet wallet(
    String name, {
    WalletStatus status = WalletStatus.active,
    WalletSourceMode mode = WalletSourceMode.notification,
    String? package,
  }) =>
      Wallet(
        id: 'id-$name',
        name: name,
        status: status,
        createdAt: at,
        sourceMode: mode,
        packageName: package,
      );

  group('list', () {
    test('is empty when nothing, an empty string or whitespace is stored', () async {
      expect(await list(), isEmpty);
      store('');
      expect(await list(), isEmpty);
      store('   \n');
      expect(await list(), isEmpty);
    });

    for (final bad in ['{oops', '{}', '"text"', '5', 'null']) {
      test('invalid configuration ($bad) fails with notification_sources_invalid', () async {
        store(bad);
        final r = await registry.list();
        expect(r, isA<Failure<List<PaymentSource>>>());
        expect((r as Failure<List<PaymentSource>>).error.code, 'notification_sources_invalid');
      });
    }

    test('malformed entries are dropped but valid ones survive', () async {
      store(jsonEncode([
        {'id': 'notification:a.b', 'displayName': 'أ', 'packageName': 'a.b', 'enabled': true},
        {'displayName': 'no id', 'packageName': 'x.y', 'enabled': true},
        {'id': 'notification:z', 'packageName': 'z', 'enabled': true},
        {'id': 'notification:', 'displayName': 'empty pkg', 'packageName': '', 'enabled': true},
        'not a map',
        42,
      ]));
      final sources = await list();
      expect(sources.map((s) => s.packageName).toList(), ['a.b']);
    });

    test('enabled is true only for the boolean true', () async {
      store(jsonEncode([
        {'id': 'n:1', 'displayName': 'a', 'packageName': 'p.one', 'enabled': true},
        {'id': 'n:2', 'displayName': 'b', 'packageName': 'p.two', 'enabled': 'true'},
        {'id': 'n:3', 'displayName': 'c', 'packageName': 'p.three', 'enabled': 1},
        {'id': 'n:4', 'displayName': 'd', 'packageName': 'p.four'},
      ]));
      final byPackage = {for (final s in await list()) s.packageName!: s.enabled};
      expect(byPackage, {'p.one': true, 'p.two': false, 'p.three': false, 'p.four': false});
    });
  });

  group('upsert', () {
    for (final c in [
      ('', 'com.a'),
      ('  ', 'com.a'),
      ('جيب', ''),
      ('جيب', '   '),
      ('جيب', 'com. ahd'),
      ('جيب', 'com.ahd\tjaib'),
    ]) {
      test('rejects name "${c.$1}" with package "${c.$2}" and stores nothing', () async {
        final r = await registry.upsert(displayName: c.$1, packageName: c.$2, enabled: true);
        expect(r, isA<Failure<void>>());
        expect((r as Failure<void>).error.code, 'notification_source_invalid');
        expect(settings.saves, 0);
        expect(await list(), isEmpty);
      });
    }

    test('trims input, builds the id from the package and stamps the clock', () async {
      await registry.upsert(displayName: '  جيب ', packageName: ' com.ahd.jaib ', enabled: true);
      final s = (await list()).single;
      expect(s.id, 'notification:com.ahd.jaib');
      expect(s.displayName, 'جيب');
      expect(s.packageName, 'com.ahd.jaib');
      expect(s.channel, PaymentChannel.notification);
      expect(s.enabled, isTrue);
      expect(settings.map[SettingKeys.notificationSources]!.updatedAt, at);
    });

    test('upserting the same package replaces the entry instead of duplicating it', () async {
      await registry.upsert(displayName: 'قديم', packageName: 'com.a', enabled: true);
      await registry.upsert(displayName: 'جديد', packageName: 'com.a', enabled: false);
      final sources = await list();
      expect(sources.length, 1);
      expect(sources.single.displayName, 'جديد');
      expect(sources.single.enabled, isFalse);
    });

    test('refuses to overwrite a corrupt configuration (nothing is lost silently)', () async {
      store('{oops');
      final r = await registry.upsert(displayName: 'x', packageName: 'com.x', enabled: true);
      expect(r, isA<Failure<void>>());
      expect(settings.map[SettingKeys.notificationSources]!.value, '{oops');
    });
  });

  group('setEnabled and remove', () {
    setUp(() async {
      await registry.upsert(displayName: 'أ', packageName: 'com.a', enabled: true);
      await registry.upsert(displayName: 'ب', packageName: 'com.b', enabled: true);
    });

    test('setEnabled changes only the targeted package', () async {
      await registry.setEnabled('com.a', false);
      final byPackage = {for (final s in await list()) s.packageName!: s.enabled};
      expect(byPackage, {'com.a': false, 'com.b': true});
    });

    test('setEnabled on an unknown package changes nothing', () async {
      final r = await registry.setEnabled('com.ghost', false);
      expect(r, isA<Success<void>>());
      expect((await list()).every((s) => s.enabled), isTrue);
      expect((await list()).length, 2);
    });

    test('setEnabled keeps id, name and the sms sender hint', () async {
      store(jsonEncode([
        {
          'id': 'notification:com.a',
          'displayName': 'أ',
          'packageName': 'com.a',
          'smsSenderHint': 'JAIB',
          'enabled': true,
        },
      ]));
      await registry.setEnabled('com.a', false);
      final s = (await list()).single;
      expect(s.id, 'notification:com.a');
      expect(s.displayName, 'أ');
      expect(s.smsSenderHint, 'JAIB');
      expect(s.enabled, isFalse);
    });

    test('remove deletes only the targeted package and tolerates unknown ones', () async {
      await registry.remove('com.a');
      expect((await list()).map((s) => s.packageName).toList(), ['com.b']);
      expect(await registry.remove('com.ghost'), isA<Success<void>>());
      expect((await list()).length, 1);
    });
  });

  group('ensureWalletSources', () {
    test('adds notification wallets that have a package and skips every other kind', () async {
      final r = await registry.ensureWalletSources([
        wallet('جيب', package: 'com.ahd.jaib'),
        wallet('جوالي', mode: WalletSourceMode.sms, package: 'com.wecash.jawali'),
        wallet('بلا حزمة'),
        wallet('حزمة فارغة', package: '   '),
      ]);
      expect(r, isA<Success<void>>());
      final sources = await list();
      expect(sources.map((s) => s.packageName).toList(), ['com.ahd.jaib']);
      expect(sources.single.displayName, 'جيب');
    });

    test('enabled mirrors the wallet status', () async {
      await registry.ensureWalletSources([
        wallet('نشطة', package: 'com.active'),
        wallet('موقوفة', status: WalletStatus.suspended, package: 'com.suspended'),
        wallet('مؤرشفة', status: WalletStatus.archived, package: 'com.archived'),
      ]);
      final byPackage = {for (final s in await list()) s.packageName!: s.enabled};
      expect(byPackage, {'com.active': true, 'com.suspended': false, 'com.archived': false});
    });

    test('never overrides an operator choice already in the allow-list', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: false);
      await registry.ensureWalletSources([wallet('جيب', package: 'com.ahd.jaib')]);
      final s = (await list()).single;
      expect(s.enabled, isFalse);
    });

    test('is idempotent and does not rewrite storage once everything is present', () async {
      final wallets = [wallet('جيب', package: 'com.ahd.jaib')];
      await registry.ensureWalletSources(wallets);
      final savesAfterFirst = settings.saves;
      await registry.ensureWalletSources(wallets);
      await registry.ensureWalletSources(wallets);
      expect((await list()).length, 1);
      expect(settings.saves, savesAfterFirst);
    });

    test('trims the package before registering it', () async {
      await registry.ensureWalletSources([wallet('جيب', package: '  com.ahd.jaib  ')]);
      expect((await list()).single.packageName, 'com.ahd.jaib');
    });

    test('an empty wallet list is a no-op', () async {
      expect(await registry.ensureWalletSources(const []), isA<Success<void>>());
      expect(settings.saves, 0);
    });

    test('a package containing whitespace is reported, not silently registered', () async {
      final r = await registry.ensureWalletSources([wallet('سيء', package: 'bad pkg')]);
      expect(r, isA<Failure<void>>());
      expect((r as Failure<void>).error.code, 'notification_source_invalid');
      expect(await list(), isEmpty);
    });

    test('a corrupt allow-list is surfaced and left untouched', () async {
      store('{oops');
      final r = await registry.ensureWalletSources([wallet('جيب', package: 'com.ahd.jaib')]);
      expect(r, isA<Failure<void>>());
      expect(settings.map[SettingKeys.notificationSources]!.value, '{oops');
    });
  });
}
