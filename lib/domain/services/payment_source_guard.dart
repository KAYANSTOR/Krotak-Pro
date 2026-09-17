import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import 'local_payment_source_registry.dart';

/// Authorizes inbound payment events against explicitly configured payment sources.
/// Commercial processing is never allowed merely because an SMS body matches a
/// template. The source must belong to an active wallet configured for the same
/// transport and the matching template must be linked to that wallet.
final class PaymentSourceGuard {
  const PaymentSourceGuard({
    required this.wallets,
    required this.templates,
    this.notificationSources,
  });

  final WalletRepository wallets;
  final TransferTemplateRepository templates;
  final LocalPaymentSourceRegistry? notificationSources;

  Future<Result<void>> authorize(
    PaymentEvent event, {
    String? matchedTemplateId,
  }) async {
    if (event.channel == PaymentChannel.manual) return const Success(null);

    final listedWallets = await wallets.listAll();
    if (listedWallets is Failure<List<Wallet>>) return Failure(listedWallets.error);
    final activeWallets = (listedWallets as Success<List<Wallet>>).value
        .where((w) => w.status == WalletStatus.active)
        .toList(growable: false);

    Wallet? wallet;
    if (event.channel == PaymentChannel.sms) {
      final incomingSender = _normalize(event.sourceKey);
      wallet = activeWallets.where((w) {
        if (w.sourceMode != WalletSourceMode.sms) return false;
        final sender = w.senderId;
        return sender != null && sender.trim().isNotEmpty &&
            _normalize(sender) == incomingSender;
      }).firstOrNull;
    } else if (event.channel == PaymentChannel.notification) {
      final package = event.packageName?.trim();
      if (package == null || package.isEmpty) {
        return const Failure(AppFailure(
          code: 'untrusted_payment_source',
          message: 'Notification source is not configured',
        ));
      }
      wallet = activeWallets.where((w) =>
          w.sourceMode == WalletSourceMode.notification &&
          w.packageName != null &&
          w.packageName!.trim() == package).firstOrNull;
      if (wallet != null && notificationSources != null) {
        final configured = await notificationSources!.list();
        if (configured is Failure<List<PaymentSource>>) return Failure(configured.error);
        final source = (configured as Success<List<PaymentSource>>).value
            .where((s) => s.packageName == package && s.enabled)
            .firstOrNull;
        if (source == null) wallet = null;
      }
    }

    if (wallet == null) {
      return const Failure(AppFailure(
        code: 'untrusted_payment_source',
        message: 'Payment source is not linked to an active configured wallet',
      ));
    }

    final configuredTemplates = await templates.listAll();
    if (configuredTemplates is Failure<List<TransferTemplate>>) return Failure(configuredTemplates.error);
    final walletId = wallet.id;
    final liveTemplates = (configuredTemplates as Success<List<TransferTemplate>>).value
        .where((t) => t.isActive && t.walletId == walletId)
        .toList(growable: false);
    if (liveTemplates.isEmpty) {
      return const Failure(AppFailure(
        code: 'no_source_template',
        message: 'No active transfer template is linked to this payment source',
      ));
    }
    if (matchedTemplateId != null && !liveTemplates.any((t) => t.id == matchedTemplateId)) {
      return const Failure(AppFailure(
        code: 'template_source_mismatch',
        message: 'Matched template is not linked to the trusted payment source',
      ));
    }
    return const Success(null);
  }

  String _normalize(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
