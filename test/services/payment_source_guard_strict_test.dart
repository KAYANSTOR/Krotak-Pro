import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/rejection_codes.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_payment_source_registry.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';

final class _Wallets implements WalletRepository {
  _Wallets(Iterable<Wallet> initial) {
    for (final w in initial) {
      map[w.id] = w;
    }
  }

  final map = <String, Wallet>{};
  bool failList = false;

  @override
  Future<Result<Wallet?>> findById(String id) async => Success(map[id]);

  @override
  Future<Result<List<Wallet>>> listAll() async {
    if (failList) {
      return const Failure(AppFailure(code: 'wallet_list_failed', message: 'boom'));
    }
    return Success(map.values.toList(growable: false));
  }

  @override
  Future<Result<void>> save(Wallet wallet) async {
    map[wallet.id] = wallet;
    return const Success(null);
  }
}

final class _Templates implements TransferTemplateRepository {
  _Templates(Iterable<TransferTemplate> initial) : list = [...initial];

  final List<TransferTemplate> list;
  bool failList = false;

  @override
  Future<Result<List<TransferTemplate>>> listAll() async {
    if (failList) {
      return const Failure(AppFailure(code: 'template_list_failed', message: 'boom'));
    }
    return Success(List<TransferTemplate>.of(list));
  }

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
    list
      ..removeWhere((t) => t.id == template.id)
      ..add(template);
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    list.removeWhere((t) => t.id == id);
    return const Success(null);
  }
}

final class _Settings implements SettingsRepository {
  final map = <String, AppSetting>{};

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(map[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    map[setting.key] = setting;
    return const Success(null);
  }
}

final _created = DateTime.utc(2026, 1, 1);
final _at = DateTime.utc(2026, 10, 4, 10);

Wallet _wallet(
  String id, {
  String? senderId,
  WalletStatus status = WalletStatus.active,
  WalletSourceMode mode = WalletSourceMode.sms,
  String? packageName,
}) =>
    Wallet(
      id: id,
      name: 'wallet $id',
      status: status,
      createdAt: _created,
      senderId: senderId,
      sourceMode: mode,
      packageName: packageName,
    );

TransferTemplate _tpl(
  String id, {
  String? walletId,
  String? posId,
  bool active = true,
}) =>
    TransferTemplate(
      id: id,
      name: 'tpl $id',
      pattern: '{amount} {phone} {ref}',
      isActive: active,
      walletId: walletId,
      posId: posId,
    );

PaymentEvent _sms(String sender) => PaymentEvent(
      channel: PaymentChannel.sms,
      sourceKey: sender,
      body: 'x',
      receivedAt: _at,
    );

PaymentEvent _notif(String? package) => PaymentEvent(
      channel: PaymentChannel.notification,
      sourceKey: package ?? '',
      body: 'x',
      receivedAt: _at,
      packageName: package,
    );

void expectRejected(Result<void> r, String code) {
  expect(r, isA<Failure<void>>(), reason: 'expected a rejection with $code');
  expect((r as Failure<void>).error.code, code);
}

void main() {
  group('SMS authorization', () {
    late _Wallets wallets;
    late _Templates templates;
    late PaymentSourceGuard guard;

    setUp(() {
      wallets = _Wallets([
        _wallet('jaib', senderId: 'JAIB'),
        _wallet('onecash', senderId: 'ONE CASH'),
      ]);
      templates = _Templates([_tpl('t-jaib', walletId: 'jaib'), _tpl('t-one', walletId: 'onecash')]);
      guard = PaymentSourceGuard(wallets: wallets, templates: templates);
    });

    test('exact sender with an active linked template is authorized', () async {
      expect(await guard.authorize(_sms('JAIB')), isA<Success<void>>());
    });

    test('matching is exact: case and internal whitespace differences are rejected', () async {
      expectRejected(await guard.authorize(_sms('jaib')), RejectionCodes.unknownSender);
      expectRejected(await guard.authorize(_sms('  J A I B  ')), RejectionCodes.unknownSender);
      expectRejected(await guard.authorize(_sms('ONE  cash')), RejectionCodes.unknownSender);
    });

    test('a decorated sender that merely contains the configured id is rejected', () async {
      expectRejected(await guard.authorize(_sms('JAIB-PROMO')), RejectionCodes.unknownSender);
    });

    test('an unknown sender is rejected as unknownSender', () async {
      expectRejected(await guard.authorize(_sms('EVILBANK')), RejectionCodes.unknownSender);
    });

    for (final blank in ['', ' ', '   \n']) {
      test('a blank sender (${blank.codeUnits}) is rejected', () async {
        expectRejected(await guard.authorize(_sms(blank)), RejectionCodes.unknownSender);
      });
    }

    for (final tiny in ['A', 'B', 'I', 'AI', 'IB', 'JA']) {
      test('a 1-2 character sender "$tiny" can never impersonate a wallet', () async {
        expectRejected(await guard.authorize(_sms(tiny)), RejectionCodes.unknownSender);
      });
    }

    test('a 1-2 character configured id is not matched by longer unrelated senders', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([_wallet('short', senderId: 'AB')]),
        templates: _Templates([_tpl('t', walletId: 'short')]),
      );
      expect(await g.authorize(_sms('AB')), isA<Success<void>>());
      expectRejected(await g.authorize(_sms('ABCDEF')), RejectionCodes.unknownSender);
      expectRejected(await g.authorize(_sms('BANK-AB-X')), RejectionCodes.unknownSender);
    });

    test('numeric senders are matched exactly, never by digit suffix', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([_wallet('num', senderId: '777-123')]),
        templates: _Templates([_tpl('t', walletId: 'num')]),
      );
      expect(await g.authorize(_sms('777-123')), isA<Success<void>>());
      expectRejected(await g.authorize(_sms('+967 777 123')), RejectionCodes.unknownSender);
      expectRejected(await g.authorize(_sms('+967 888 123')), RejectionCodes.unknownSender);
      expectRejected(await g.authorize(_sms('12')), RejectionCodes.unknownSender);
    });

    test('a wallet with a null or blank sender never matches anything', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([
          _wallet('nosender'),
          _wallet('blank', senderId: '   '),
        ]),
        templates: _Templates([_tpl('a', walletId: 'nosender'), _tpl('b', walletId: 'blank')]),
      );
      for (final s in ['', 'JAIB', 'anything']) {
        expectRejected(await g.authorize(_sms(s)), RejectionCodes.unknownSender);
      }
    });

    test('a wallet configured for notifications still accepts its SMS short-code', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([
          _wallet('jaib', senderId: 'JAIB', mode: WalletSourceMode.notification, packageName: 'com.ahd.jaib'),
        ]),
        templates: _Templates([_tpl('t', walletId: 'jaib')]),
      );
      expect(await g.authorize(_sms('JAIB')), isA<Success<void>>());
    });

    test('suspended and archived wallets are rejected, and reactivation is honoured live', () async {
      for (final status in [WalletStatus.suspended, WalletStatus.archived]) {
        wallets.map['jaib'] = _wallet('jaib', senderId: 'JAIB', status: status);
        expectRejected(await guard.authorize(_sms('JAIB')), RejectionCodes.unknownSender);
      }
      wallets.map['jaib'] = _wallet('jaib', senderId: 'JAIB');
      expect(await guard.authorize(_sms('JAIB')), isA<Success<void>>());
    });

    test('a suspended wallet does not shadow a second active wallet with the same sender', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([
          _wallet('old', senderId: 'JAIB', status: WalletStatus.suspended),
          _wallet('new', senderId: 'JAIB'),
        ]),
        templates: _Templates([_tpl('t-new', walletId: 'new')]),
      );
      expect(await g.authorize(_sms('JAIB'), matchedTemplateId: 't-new'), isA<Success<void>>());
    });

    test('an active wallet without any template is rejected with no_source_template', () async {
      templates.list.removeWhere((t) => t.walletId == 'jaib');
      expectRejected(await guard.authorize(_sms('JAIB')), 'no_source_template');
    });

    test('deactivating the only template blocks the wallet immediately', () async {
      templates.list
        ..removeWhere((t) => t.id == 't-jaib')
        ..add(_tpl('t-jaib', walletId: 'jaib', active: false));
      expectRejected(await guard.authorize(_sms('JAIB')), 'no_source_template');
    });

    test('templates of other wallets, POS templates and unlinked templates do not authorize', () async {
      final g = PaymentSourceGuard(
        wallets: _Wallets([_wallet('jaib', senderId: 'JAIB')]),
        templates: _Templates([
          _tpl('other', walletId: 'someone-else'),
          _tpl('pos', posId: 'pos-1'),
          _tpl('loose'),
        ]),
      );
      expectRejected(await g.authorize(_sms('JAIB')), 'no_source_template');
    });

    test('a matched template of another wallet is a template_source_mismatch', () async {
      expectRejected(
        await guard.authorize(_sms('JAIB'), matchedTemplateId: 't-one'),
        'template_source_mismatch',
      );
    });

    test('a matched template of the same wallet passes, an unknown id does not', () async {
      expect(await guard.authorize(_sms('JAIB'), matchedTemplateId: 't-jaib'), isA<Success<void>>());
      expectRejected(
        await guard.authorize(_sms('JAIB'), matchedTemplateId: 'no-such-template'),
        'template_source_mismatch',
      );
    });

    test('a matched but deactivated template is a mismatch', () async {
      templates.list.add(_tpl('t-jaib-off', walletId: 'jaib', active: false));
      expectRejected(
        await guard.authorize(_sms('JAIB'), matchedTemplateId: 't-jaib-off'),
        'template_source_mismatch',
      );
    });

    test('repository failures fail closed and surface their own error', () async {
      wallets.failList = true;
      expectRejected(await guard.authorize(_sms('JAIB')), 'wallet_list_failed');
      wallets.failList = false;
      templates.failList = true;
      expectRejected(await guard.authorize(_sms('JAIB')), 'template_list_failed');
    });

    test('the manual channel is never auto-authorized as a payment source', () async {
      final g = PaymentSourceGuard(wallets: _Wallets(const []), templates: _Templates(const []));
      final r = await g.authorize(
        PaymentEvent(channel: PaymentChannel.manual, sourceKey: 'cashier', body: 'x', receivedAt: _at),
      );
      expectRejected(r, manualRequiresReviewCode);
    });
  });

  group('notification authorization', () {
    late _Wallets wallets;
    late _Templates templates;
    late _Settings settings;
    late LocalPaymentSourceRegistry registry;

    PaymentSourceGuard guardWithRegistry() => PaymentSourceGuard(
          wallets: wallets,
          templates: templates,
          notificationSources: registry,
        );

    setUp(() {
      wallets = _Wallets([
        _wallet('jaib', senderId: 'JAIB', mode: WalletSourceMode.notification, packageName: 'com.ahd.jaib'),
        _wallet('jawali', senderId: 'JAWALI', mode: WalletSourceMode.sms, packageName: 'com.wecash.jawali'),
      ]);
      templates = _Templates([_tpl('t-jaib', walletId: 'jaib'), _tpl('t-jawali', walletId: 'jawali')]);
      settings = _Settings();
      registry = LocalPaymentSourceRegistry(settings: settings, clock: FixedClock(_at));
    });

    test('matching package on a notification wallet with a template is authorized', () async {
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expect(await g.authorize(_notif('com.ahd.jaib')), isA<Success<void>>());
    });

    for (final pkg in [null, '', '   ']) {
      test('a missing package ("$pkg") is rejected', () async {
        final g = PaymentSourceGuard(wallets: wallets, templates: templates);
        expectRejected(await g.authorize(_notif(pkg)), RejectionCodes.unknownSender);
      });
    }

    test('an unknown package is rejected', () async {
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expectRejected(await g.authorize(_notif('com.evil.app')), RejectionCodes.unknownSender);
    });

    test('an sms-mode wallet never authorizes a notification, even with its package', () async {
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expectRejected(await g.authorize(_notif('com.wecash.jawali')), RejectionCodes.unknownSender);
    });

    test('package comparison is exact: no prefix, suffix or case tolerance', () async {
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      for (final p in ['com.ahd.jaib.fake', 'com.ahd', 'COM.AHD.JAIB', 'x.com.ahd.jaib']) {
        expectRejected(await g.authorize(_notif(p)), RejectionCodes.unknownSender);
      }
    });

    test('padding around the package is ignored on both sides', () async {
      wallets.map['jaib'] = _wallet(
        'jaib',
        senderId: 'JAIB',
        mode: WalletSourceMode.notification,
        packageName: '  com.ahd.jaib ',
      );
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expect(await g.authorize(_notif(' com.ahd.jaib  ')), isA<Success<void>>());
    });

    test('a suspended notification wallet is rejected', () async {
      wallets.map['jaib'] = _wallet(
        'jaib',
        senderId: 'JAIB',
        status: WalletStatus.suspended,
        mode: WalletSourceMode.notification,
        packageName: 'com.ahd.jaib',
      );
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expectRejected(await g.authorize(_notif('com.ahd.jaib')), RejectionCodes.unknownSender);
    });

    test('without a template the notification wallet is rejected with no_source_template', () async {
      templates.list.clear();
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expectRejected(await g.authorize(_notif('com.ahd.jaib')), 'no_source_template');
    });

    test('an enabled entry in the notification allow-list authorizes', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: true);
      expect(await guardWithRegistry().authorize(_notif('com.ahd.jaib')), isA<Success<void>>());
    });

    test('a disabled allow-list entry blocks even an active wallet with a template', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: false);
      expectRejected(await guardWithRegistry().authorize(_notif('com.ahd.jaib')), RejectionCodes.unknownSender);
    });

    test('a package missing from a configured allow-list is blocked', () async {
      await registry.upsert(displayName: 'غيره', packageName: 'com.other.app', enabled: true);
      expectRejected(await guardWithRegistry().authorize(_notif('com.ahd.jaib')), RejectionCodes.unknownSender);
    });

    test('toggling the allow-list entry flips authorization on the very next event', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: true);
      final g = guardWithRegistry();
      expect(await g.authorize(_notif('com.ahd.jaib')), isA<Success<void>>());
      await registry.setEnabled('com.ahd.jaib', false);
      expectRejected(await g.authorize(_notif('com.ahd.jaib')), RejectionCodes.unknownSender);
      await registry.setEnabled('com.ahd.jaib', true);
      expect(await g.authorize(_notif('com.ahd.jaib')), isA<Success<void>>());
    });

    test('a corrupt allow-list fails closed with notification_sources_invalid', () async {
      settings.map[SettingKeys.notificationSources] =
          AppSetting(key: SettingKeys.notificationSources, value: '{oops', updatedAt: _at);
      expectRejected(await guardWithRegistry().authorize(_notif('com.ahd.jaib')), 'notification_sources_invalid');
    });

    test('a matched template of another wallet is a mismatch on notifications too', () async {
      final g = PaymentSourceGuard(wallets: wallets, templates: templates);
      expectRejected(
        await g.authorize(_notif('com.ahd.jaib'), matchedTemplateId: 't-jawali'),
        'template_source_mismatch',
      );
    });
  });

  group('diagnose', () {
    late _Wallets wallets;
    late _Templates templates;
    late _Settings settings;
    late LocalPaymentSourceRegistry registry;
    late PaymentSourceGuard guard;

    setUp(() {
      wallets = _Wallets([
        _wallet('jaib', senderId: 'JAIB', mode: WalletSourceMode.notification, packageName: 'com.ahd.jaib'),
        _wallet('floosak', senderId: 'FLOOSAK'),
      ]);
      templates = _Templates([
        _tpl('t-jaib-a', walletId: 'jaib'),
        _tpl('t-jaib-b', walletId: 'jaib'),
        _tpl('t-jaib-off', walletId: 'jaib', active: false),
        _tpl('t-floosak', walletId: 'floosak'),
      ]);
      settings = _Settings();
      registry = LocalPaymentSourceRegistry(settings: settings, clock: FixedClock(_at));
      guard = PaymentSourceGuard(wallets: wallets, templates: templates, notificationSources: registry);
    });

    Future<PaymentSourceDiagnosis> diag(PaymentEvent e, {String? matched}) async =>
        ((await guard.diagnose(e, matchedTemplateId: matched)) as Success<PaymentSourceDiagnosis>).value;

    test('an authorized sms event reports the wallet and only its active templates', () async {
      final d = await diag(_sms(' Floosak '));
      expect(d.authorized, isTrue);
      expect(d.walletId, 'floosak');
      expect(d.walletStatus, WalletStatus.active);
      expect(d.walletSourceMode, WalletSourceMode.sms);
      expect(d.normalizedSource, 'floosak');
      expect(d.activeTemplateIds, ['t-floosak']);
      expect(d.failureCode, isNull);
    });

    test('inactive templates are excluded from activeTemplateIds', () async {
      final d = await diag(_sms('JAIB'));
      expect(d.activeTemplateIds.toSet(), {'t-jaib-a', 't-jaib-b'});
    });

    test('an unknown sender reports the failure and no wallet', () async {
      final d = await diag(_sms('E V I L'));
      expect(d.authorized, isFalse);
      expect(d.walletId, isNull);
      expect(d.activeTemplateIds, isEmpty);
      expect(d.failureCode, RejectionCodes.unknownSender);
      expect(d.normalizedSource, 'evil');
    });

    test('a suspended wallet is not reported as the source', () async {
      wallets.map['floosak'] = _wallet('floosak', senderId: 'FLOOSAK', status: WalletStatus.suspended);
      final d = await diag(_sms('FLOOSAK'));
      expect(d.authorized, isFalse);
      expect(d.walletId, isNull);
      expect(d.failureCode, RejectionCodes.unknownSender);
    });

    test('a disabled notification source is found but flagged as not enabled', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: false);
      final d = await diag(_notif('com.ahd.jaib'));
      expect(d.authorized, isFalse);
      expect(d.sourceEnabled, isFalse);
      expect(d.walletId, 'jaib');
      expect(d.activeTemplateIds, isEmpty);
      expect(d.packageName, 'com.ahd.jaib');
    });

    test('an enabled notification source is authorized with its templates', () async {
      await registry.upsert(displayName: 'جيب', packageName: 'com.ahd.jaib', enabled: true);
      final d = await diag(_notif('com.ahd.jaib'));
      expect(d.authorized, isTrue);
      expect(d.sourceEnabled, isTrue);
      expect(d.walletSourceMode, WalletSourceMode.notification);
      expect(d.activeTemplateIds.toSet(), {'t-jaib-a', 't-jaib-b'});
    });

    test('the manual channel is reported as review-required, not authorized', () async {
      final d = await diag(
        PaymentEvent(channel: PaymentChannel.manual, sourceKey: 'cashier', body: 'x', receivedAt: _at),
      );
      expect(d.authorized, isFalse);
      expect(d.failureCode, manualRequiresReviewCode);
      expect(d.sourceEnabled, isTrue);
      expect(d.walletId, isNull);
    });

    test('a mismatching template is reported with its owner and the mismatch code', () async {
      final d = await diag(_sms('JAIB'), matched: 't-floosak');
      expect(d.authorized, isFalse);
      expect(d.failureCode, 'template_source_mismatch');
      expect(d.matchedTemplateId, 't-floosak');
      expect(d.matchedTemplateName, 'tpl t-floosak');
      expect(d.matchedTemplateWalletId, 'floosak');
      expect(d.walletId, 'jaib');
    });

    test('a correct matched template is echoed back without failure', () async {
      final d = await diag(_sms('JAIB'), matched: 't-jaib-a');
      expect(d.authorized, isTrue);
      expect(d.matchedTemplateWalletId, 'jaib');
      expect(d.failureCode, isNull);
    });

    test('toJson exposes enum names and the decision for the rejected-messages screen', () async {
      final json = (await diag(_sms('E V I L'))).toJson();
      expect(json['channel'], 'sms');
      expect(json['authorized'], false);
      expect(json['failureCode'], RejectionCodes.unknownSender);
      expect(json['walletStatus'], isNull);
      expect(() => jsonEncode(json), returnsNormally);

      final ok = (await diag(_sms('FLOOSAK'))).toJson();
      expect(ok['walletStatus'], 'active');
      expect(ok['walletSourceMode'], 'sms');
    });

    test('diagnose propagates repository failures instead of guessing', () async {
      templates.failList = true;
      final r = await guard.diagnose(_sms('JAIB'));
      expect(r, isA<Failure<PaymentSourceDiagnosis>>());
      expect((r as Failure<PaymentSourceDiagnosis>).error.code, 'template_list_failed');
    });
  });
}
