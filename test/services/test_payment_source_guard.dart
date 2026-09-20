import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/core/clock.dart';

PaymentSourceGuard trustedPaymentSourceGuard({
  String senderId = 'JAIB',
  String walletId = 'wallet-test',
  String templateId = 'tpl-1',
}) {
  return PaymentSourceGuard(
    wallets: _WalletRepositoryFake(
      Wallet(
        id: walletId,
        name: 'Test Wallet',
        status: WalletStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        senderId: senderId,
        sourceMode: WalletSourceMode.sms,
      ),
    ),
    templates: _TransferTemplateRepositoryFake(
      TransferTemplate(
        id: templateId,
        name: 'Test Template',
        pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
        isActive: true,
        walletId: walletId,
      ),
    ),
  );
}


PaymentSourceGuard trustedPosPaymentSourceGuard() {
  final settings = _SettingsRepositoryFake();
  final registry = LocalPosAccountRegistry(settings: settings, clock: _TestClock());
  registry.save(
    const PosAccount(
      posId: 'pos-1',
      customerId: 'customer-1',
      name: 'نقطة البيع',
      identifiers: ['777000111'],
    ),
  );
  return PaymentSourceGuard(
    wallets: _WalletRepositoryFake(
      Wallet(
        id: 'wallet-test',
        name: 'Test Wallet',
        status: WalletStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        senderId: 'JAIB',
      ),
    ),
    templates: _TransferTemplateRepositoryFake(
      const TransferTemplate(
        id: 'tpl-pos-1',
        name: 'قالب نقطة البيع',
        pattern: '{phone} {amount}',
        isActive: true,
        posId: 'pos-1',
        requireReference: false,
      ),
    ),
    posAccounts: registry,
  );
}

final class _SettingsRepositoryFake implements SettingsRepository {
  final Map<String, AppSetting> values = {};

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(values[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting;
    return const Success(null);
  }
}

final class _TestClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 20);
}

final class _WalletRepositoryFake implements WalletRepository {
  _WalletRepositoryFake(this.wallet);
  final Wallet wallet;

  @override
  Future<Result<Wallet?>> findById(String id) async =>
      Success(id == wallet.id ? wallet : null);

  @override
  Future<Result<List<Wallet>>> listAll() async => Success([wallet]);

  @override
  Future<Result<void>> save(Wallet value) async => const Success(null);
}

final class _TransferTemplateRepositoryFake
    implements TransferTemplateRepository {
  _TransferTemplateRepositoryFake(this.template);
  final TransferTemplate template;

  @override
  Future<Result<void>> delete(String id) async => const Success(null);

  @override
  Future<Result<TransferTemplate?>> findById(String id) async =>
      Success(id == template.id ? template : null);

  @override
  Future<Result<List<TransferTemplate>>> listAll() async => Success([template]);

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(walletId == template.walletId ? [template] : const []);

  @override
  Future<Result<void>> save(TransferTemplate value) async => const Success(null);
}
