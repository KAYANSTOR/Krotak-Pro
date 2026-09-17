import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';

PaymentSourceGuard trustedPaymentSourceGuard() {
  final wallets = _FakeWallets([
    Wallet(
      id: 'wallet-bank',
      name: 'Bank SMS',
      status: WalletStatus.active,
      createdAt: DateTime.utc(2026, 9, 1),
      senderId: 'bank',
      sourceMode: WalletSourceMode.sms,
    ),
    Wallet(
      id: 'wallet-jib',
      name: 'JIB Notification',
      status: WalletStatus.active,
      createdAt: DateTime.utc(2026, 9, 1),
      sourceMode: WalletSourceMode.notification,
      packageName: 'com.wallet.jib',
    ),
  ]);
  final templates = _FakeTemplates([
    const TransferTemplate(
      id: 'template-bank',
      name: 'Bank transfer',
      pattern: 'transfer {amount} to {phone} ref {ref}',
      isActive: true,
      walletId: 'wallet-bank',
    ),
    const TransferTemplate(
      id: 'template-jib',
      name: 'JIB transfer',
      pattern: 'push {amount} to {phone} ref {ref}',
      isActive: true,
      walletId: 'wallet-jib',
    ),
  ]);
  return PaymentSourceGuard(wallets: wallets, templates: templates);
}

final class _FakeWallets implements WalletRepository {
  _FakeWallets(this.items);
  final List<Wallet> items;

  @override
  Future<Result<Wallet?>> findById(String id) async =>
      Success(items.where((e) => e.id == id).firstOrNull);

  @override
  Future<Result<List<Wallet>>> listAll() async => Success(items);

  @override
  Future<Result<void>> save(Wallet wallet) async {
    items.removeWhere((e) => e.id == wallet.id);
    items.add(wallet);
    return const Success(null);
  }
}

final class _FakeTemplates implements TransferTemplateRepository {
  _FakeTemplates(this.items);
  final List<TransferTemplate> items;

  @override
  Future<Result<void>> delete(String id) async {
    items.removeWhere((e) => e.id == id);
    return const Success(null);
  }

  @override
  Future<Result<TransferTemplate?>> findById(String id) async =>
      Success(items.where((e) => e.id == id).firstOrNull);

  @override
  Future<Result<List<TransferTemplate>>> listAll() async => Success(items);

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(items.where((e) => e.walletId == walletId).toList());

  @override
  Future<Result<void>> save(TransferTemplate template) async {
    items.removeWhere((e) => e.id == template.id);
    items.add(template);
    return const Success(null);
  }
}
