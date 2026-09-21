import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';

import '../helpers/in_memory_repositories.dart';

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 17, 12);
}

final class _Ids implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) => '$prefix-${++n}';
}

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

final class _MemTemplates implements TransferTemplateRepository {
  final list = <TransferTemplate>[];

  @override
  Future<Result<List<TransferTemplate>>> listAll() async => Success(list);

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(list.where((t) => t.walletId == walletId).toList());

  @override
  Future<Result<TransferTemplate?>> findById(String id) async {
    for (final t in list) {
      if (t.id == id) return Success(t);
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> save(TransferTemplate template) async {
    list.removeWhere((t) => t.id == template.id);
    list.add(template);
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    list.removeWhere((t) => t.id == id);
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
  test('wallet switch suspend persists and blocks payment source', () async {
    final wallets = _MemWallets();
    final templates = _MemTemplates();
    final settings = _MemSettings();
    final audit = InMemoryAuditLogRepository();
    final catalog = LocalWalletCatalogService(
      wallets: wallets,
      auditLogs: audit,
      settings: settings,
      clock: _Clock(),
      ids: _Ids(),
    );

    final saved = await catalog.saveWallet(
      name: 'جيب',
      senderId: 'JAIB',
      sourceMode: WalletSourceMode.notification,
      packageName: 'com.ahd.jaib',
    );
    expect(saved, isA<Success<Wallet>>());
    final wallet = (saved as Success<Wallet>).value;

    await templates.save(
      TransferTemplate(
        id: 'tpl-1',
        name: 'جيب',
        pattern: 'اضيف {amount} من {phone}',
        isActive: true,
        walletId: wallet.id,
      ),
    );

    final guardActive = PaymentSourceGuard(
      wallets: wallets,
      templates: templates,
    );
    final ok = await guardActive.authorize(
      PaymentEvent(
        channel: PaymentChannel.notification,
        sourceKey: 'com.ahd.jaib',
        body: 'x',
        receivedAt: DateTime.utc(2026, 9, 17),
        packageName: 'com.ahd.jaib',
      ),
    );
    expect(ok, isA<Success<void>>());

    final toggled = await catalog.updateWallet(
      id: wallet.id,
      name: wallet.name,
      status: WalletStatus.suspended,
      senderId: wallet.senderId,
      sourceMode: wallet.sourceMode,
      packageName: wallet.packageName,
    );
    expect(toggled, isA<Success<Wallet>>());
    expect((toggled as Success<Wallet>).value.status, WalletStatus.suspended);
    expect(wallets.map[wallet.id]!.status, WalletStatus.suspended);

    final blocked = await guardActive.authorize(
      PaymentEvent(
        channel: PaymentChannel.notification,
        sourceKey: 'com.ahd.jaib',
        body: 'x',
        receivedAt: DateTime.utc(2026, 9, 17),
        packageName: 'com.ahd.jaib',
      ),
    );
    expect(blocked, isA<Failure>());
  });
  test('seeds the four built-in wallet notification packages', () async {
    final wallets = _MemWallets();
    final settings = _MemSettings();
    final catalog = LocalWalletCatalogService(
      wallets: wallets,
      auditLogs: InMemoryAuditLogRepository(),
      settings: settings,
      clock: _Clock(),
      ids: _Ids(),
    );

    final seeded = await catalog.ensureDefaultWallets();
    expect(seeded, isA<Success<void>>());

    final raw = settings.map[SettingKeys.notificationSources]?.value;
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!);
    final packages = (decoded as List)
        .whereType<Map>()
        .map((row) => row['packageName']?.toString())
        .whereType<String>()
        .toSet();
    expect(packages, {
      'com.ahd.jaib',
      'com.wecash.jawali',
      'com.one.onecustomer',
      'co.ysys.floosak',
    });
  });

  test('notification package authorizes even when wallet primary mode is SMS', () async {
    final wallets = _MemWallets();
    final settings = _MemSettings();
    final wallet = Wallet(
      id: 'wallet-jawali',
      name: 'جوالي',
      status: WalletStatus.active,
      createdAt: DateTime.utc(2026, 9, 17),
      senderId: 'JAWALI',
      sourceMode: WalletSourceMode.sms,
      packageName: 'com.wecash.jawali',
    );
    await wallets.save(wallet);
    final templates = _MemTemplates();
    await templates.save(
      TransferTemplate(
        id: 'tpl-jawali',
        name: 'جوالي إشعار',
        pattern: 'test {amount} {phone}',
        isActive: true,
        walletId: wallet.id,
      ),
    );
    await settings.save(
      AppSetting(
        key: SettingKeys.notificationSources,
        value: jsonEncode([
          {
            'id': 'notification:com.wecash.jawali',
            'displayName': 'جوالي',
            'channel': 'notification',
            'packageName': 'com.wecash.jawali',
            'enabled': true,
          },
        ]),
        updatedAt: DateTime.utc(2026, 9, 17),
      ),
    );

    final guard = PaymentSourceGuard(
      wallets: wallets,
      templates: templates,
      notificationSources: LocalPaymentSourceRegistry(
        settings: settings,
        clock: _Clock(),
      ),
    );
    final result = await guard.authorize(
      const PaymentEvent(
        channel: PaymentChannel.notification,
        sourceKey: 'notification:com.wecash.jawali',
        body: 'test',
        receivedAt: null,
        packageName: 'com.wecash.jawali',
      ),
    );
    expect(result, isA<Success<void>>());
  });
}
