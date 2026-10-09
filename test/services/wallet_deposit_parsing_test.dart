import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/default_wallet_specs.dart';
import 'package:net_app/domain/services/default_wallet_templates_seeder.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

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
  final now = DateTime.utc(2026, 10, 9, 9);
  late _MemWallets wallets;
  late _MemSettings settings;
  late InMemoryTransferTemplateRepository templates;
  late LocalMessageParser parser;
  late Map<String, List<TransferTemplate>> byWalletName;

  setUp(() async {
    wallets = _MemWallets();
    settings = _MemSettings();
    templates = InMemoryTransferTemplateRepository();
    final catalog = LocalWalletCatalogService(
      wallets: wallets,
      auditLogs: InMemoryAuditLogRepository(),
      settings: settings,
      clock: FixedClock(now),
      ids: SequentialIdGenerator(),
    );
    expect(await catalog.ensureDefaultWallets(), isA<Success<void>>());
    final seeder = DefaultWalletTemplatesSeeder(
      wallets: wallets,
      templates: templates,
      settings: settings,
      clock: FixedClock(now),
      ids: SequentialIdGenerator(),
    );
    expect(await seeder.seedIfNeeded(), isA<Success<int>>());

    final allTemplates =
        ((await templates.listAll()) as Success<List<TransferTemplate>>).value;
    final allWallets =
        ((await wallets.listAll()) as Success<List<Wallet>>).value;
    byWalletName = {
      for (final w in allWallets)
        w.name: allTemplates
            .where((t) => t.walletId == w.id && t.isActive)
            .toList(growable: false),
    };
    parser = LocalMessageParser(templates: allTemplates);
  });

  ParsedTransfer parseFor(String walletName, String body) {
    final ids = (byWalletName[walletName] ?? const <TransferTemplate>[])
        .map((t) => t.id)
        .toSet();
    expect(ids, isNotEmpty, reason: 'لا توجد قوالب مزروعة للمحفظة $walletName');
    final result = parser.parseForSource(
      IncomingMessage(
        id: 'm-$walletName',
        sender: walletName,
        body: body,
        receivedAt: now,
        status: MessageProcessingStatus.received,
      ),
      templateIds: ids,
    );
    expect(result, isA<Success<ParsedTransfer>>(), reason: 'body: $body');
    return (result as Success<ParsedTransfer>).value;
  }

  group('جيب — Jaib', () {
    test('base format: amount and phone identifier, balance ignored', () {
      final p = parseFor(
        'جيب',
        'اضيف 500ر.ي تحويل مشترك رص:515920ر.ي من علي القواتي 715813555',
      );
      expect(p.amount.minorUnits, 50000);
      expect(p.customerIdentifier, '715813555');
      expect(p.identifierType, TransferIdentifierType.phone);
      expect(p.reference, '515920');
    });

    test('offline format keeps the composed name and the -77 suffix', () {
      final p = parseFor(
        'جيب',
        'اضيف 200 ر.ي تحويل مشترك رص:414445 ر.ي من روضه نعمان اسم البعداني -77',
      );
      expect(p.amount.minorUnits, 20000);
      expect(p.customerIdentifier, 'روضه نعمان اسم البعداني -77');
      expect(p.identifierType, TransferIdentifierType.account);
    });

    test('alternate number format is accepted as a phone identifier', () {
      final p = parseFor(
        'جيب',
        'اضيف 500ر.ي تحويل مشترك رص:255265ر.ي من 8483883',
      );
      expect(p.amount.minorUnits, 50000);
      expect(p.customerIdentifier, '8483883');
      expect(p.identifierType, TransferIdentifierType.phone);
    });
  });

  group('جوالي — Jawali', () {
    test('extracts amount and agent phone, ignoring the balance', () {
      final p = parseFor(
        'جوالي',
        'استلمت مبلغ 200 YER من 733332303 رصيدك هو 245',
      );
      expect(p.amount.minorUnits, 20000);
      expect(p.customerIdentifier, '733332303');
      expect(p.identifierType, TransferIdentifierType.phone);
    });

    test('strips a leading English letter for matching, keeps raw id', () {
      final p = parseFor(
        'جوالي',
        'استلمت مبلغ 200 YER من M773086403 رصيدك هو 245',
      );
      expect(p.amount.minorUnits, 20000);
      expect(p.customerIdentifier, '773086403');
      expect(p.identifierType, TransferIdentifierType.phone);
      expect(p.rawIdentifier, 'M773086403');
    });
  });

  group('أم فلوس — MFloos', () {
    test('extracts name before the reference and ignores the reference', () {
      final p = parseFor(
        'أم فلوس',
        'تم إيداع مبلغ 300.00 YER من: منيره جبر المرجع:939493993',
      );
      expect(p.amount.minorUnits, 30000);
      expect(p.customerIdentifier, 'منيره جبر');
      expect(p.identifierType, TransferIdentifierType.account);
      expect(p.reference, '939493993');
    });
  });

  group('فلوسك — Floosak', () {
    test('extracts name and amount, ignoring the balance', () {
      final p = parseFor(
        'فلوسك',
        'استلمت حوالة من بسام الشيباني بمبلغ 250.00 ر.ي رصيدك 250.00 ر.ي',
      );
      expect(p.amount.minorUnits, 25000);
      expect(p.customerIdentifier, 'بسام الشيباني');
      expect(p.identifierType, TransferIdentifierType.account);
    });
  });

  group('الكريمي — KuraimiLMB', () {
    test('extracts the account holder name and amount', () {
      final p = parseFor(
        'الكريمي',
        'أودع/احمد جابر حسن المنتصر لحسابك مبلغ 600 رصيدك 10030 YER',
      );
      expect(p.amount.minorUnits, 60000);
      expect(p.customerIdentifier, 'احمد جابر حسن المنتصر');
      expect(p.identifierType, TransferIdentifierType.account);
    });
  });

  group('ون كاش — ONE Cash', () {
    test('extracts the composed name and amount, ignoring the balance', () {
      final p = parseFor(
        'ون كاش',
        'استملت 200.00 من وسام مرشد علي حمود رصيدك هوه 252.33 ر.ي',
      );
      expect(p.amount.minorUnits, 20000);
      expect(p.customerIdentifier, 'وسام مرشد علي حمود');
      expect(p.identifierType, TransferIdentifierType.account);
    });
  });

  group('official Sender IDs', () {
    test('all six wallets are seeded active with their official Sender ID',
        () async {
      final list = ((await wallets.listAll()) as Success<List<Wallet>>).value;
      expect(list.length, 6);
      final byName = {for (final w in list) w.name: w};
      expect(byName['جيب']!.senderId, 'Jaib');
      expect(byName['جوالي']!.senderId, 'Jawali');
      expect(byName['أم فلوس']!.senderId, 'MFloos');
      expect(byName['فلوسك']!.senderId, 'Floosak');
      expect(byName['الكريمي']!.senderId, 'KuraimiLMB');
      expect(byName['ون كاش']!.senderId, 'ONE Cash');
      expect(
        list.every((w) => w.status == WalletStatus.active),
        isTrue,
        reason: 'لا تُزرع أي محفظة معتمدة وهي غير مفعّلة',
      );
    });

    test('matching is exact — no partial or case-insensitive match', () {
      expect(DefaultWalletSpecs.officialSenderIds, <String>[
        'Jaib',
        'Jawali',
        'MFloos',
        'Floosak',
        'KuraimiLMB',
        'ONE Cash',
      ]);
      expect(DefaultWalletSpecs.matchesOfficialSenderId('Jaib'), isTrue);
      expect(DefaultWalletSpecs.matchesOfficialSenderId('  ONE Cash  '), isTrue);
      expect(DefaultWalletSpecs.matchesOfficialSenderId('JAIB'), isFalse);
      expect(DefaultWalletSpecs.matchesOfficialSenderId('Jaib-Promo'), isFalse);
      expect(DefaultWalletSpecs.matchesOfficialSenderId('MFloos '), isFalse);
      expect(DefaultWalletSpecs.matchesOfficialSenderId(''), isFalse);
      expect(DefaultWalletSpecs.awaitingOfficialSenderId, isEmpty);
    });

    test('every seeded template is linked to its wallet', () async {
      final allTemplates =
          ((await templates.listAll()) as Success<List<TransferTemplate>>).value;
      expect(allTemplates, isNotEmpty);
      expect(
        allTemplates.every((t) => (t.walletId ?? '').isNotEmpty),
        isTrue,
        reason: 'قالب بلا محفظة = رسالة مرفوضة بـno_source_template',
      );
    });
  });
}
