import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';

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
