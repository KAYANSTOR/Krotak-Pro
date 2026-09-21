import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/trust_unknown_payment_source_service.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  test('approve creates wallet + draft template for unknown sender', () async {
    final wallets = _MemWallets();
    final settings = _MemSettings();
    final templates = InMemoryTransferTemplateRepository();
    final messages = InMemoryMessageRepository();
    final audit = InMemoryAuditLogRepository();
    final clock = SystemClock();
    final ids = SequentialIdGenerator();
    final catalog = LocalWalletCatalogService(
      wallets: wallets,
      auditLogs: audit,
      settings: settings,
      clock: clock,
      ids: ids,
    );
    final service = TrustUnknownPaymentSourceService(
      walletCatalog: catalog,
      wallets: wallets,
      templates: templates,
      messages: messages,
      auditLogs: audit,
      clock: clock,
      ids: ids,
    );
    final msg = IncomingMessage(
      id: 'm1',
      sender: 'JAIB-NEW',
      body: 'تم تحويل 1000 الى 777000111 رقم العملية 99',
      receivedAt: DateTime.utc(2026, 9, 21),
      status: MessageProcessingStatus.rejected,
    );
    final result = await service.approve(message: msg);
    expect(result, isA<Success<Wallet>>());
    final wallet = (result as Success<Wallet>).value;
    expect(wallet.senderId, 'JAIB-NEW');
    final listed = await templates.listAll();
    expect((listed as Success<List<TransferTemplate>>).value, isNotEmpty);
    expect(
      audit.logs.any((l) => l.action == 'payment_source_trusted'),
      isTrue,
    );
  });

  test('approve reuses existing active wallet with same sender', () async {
    final wallets = _MemWallets();
    final existing = Wallet(
      id: 'w1',
      name: 'جيب',
      status: WalletStatus.active,
      createdAt: DateTime.utc(2026, 1, 1),
      senderId: 'JAIB',
    );
    await wallets.save(existing);
    final settings = _MemSettings();
    final templates = InMemoryTransferTemplateRepository();
    final service = TrustUnknownPaymentSourceService(
      walletCatalog: LocalWalletCatalogService(
        wallets: wallets,
        auditLogs: InMemoryAuditLogRepository(),
        settings: settings,
        clock: SystemClock(),
        ids: SequentialIdGenerator(),
      ),
      wallets: wallets,
      templates: templates,
      messages: InMemoryMessageRepository(),
      auditLogs: InMemoryAuditLogRepository(),
      clock: SystemClock(),
      ids: SequentialIdGenerator(),
    );
    final result = await service.approve(
      message: IncomingMessage(
        id: 'm2',
        sender: 'jaib',
        body: 'x',
        receivedAt: DateTime.utc(2026, 9, 21),
        status: MessageProcessingStatus.rejected,
      ),
    );
    expect((result as Success<Wallet>).value.id, 'w1');
    final listed = await templates.listAll();
    expect((listed as Success<List<TransferTemplate>>).value, isEmpty);
  });
}

final class _MemWallets implements WalletRepository {
  final Map<String, Wallet> store = {};

  @override
  Future<Result<void>> save(Wallet wallet) async {
    store[wallet.id] = wallet;
    return const Success(null);
  }

  @override
  Future<Result<Wallet?>> findById(String id) async => Success(store[id]);

  @override
  Future<Result<List<Wallet>>> listAll() async => Success(store.values.toList());
}

final class _MemSettings implements SettingsRepository {
  final Map<String, AppSetting> store = {};

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(store[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    store[setting.key] = setting;
    return const Success(null);
  }
}
