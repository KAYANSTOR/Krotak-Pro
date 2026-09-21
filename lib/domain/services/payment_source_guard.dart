import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import 'local_payment_source_registry.dart';
import 'local_pos_account_registry.dart';

/// Authorizes inbound payment events against explicitly configured payment sources.
/// Commercial processing is never allowed merely because an SMS body matches a
/// template. The source must belong to an active wallet configured for the same
/// transport and the matching template must be linked to that wallet.
final class PaymentSourceGuard {
  const PaymentSourceGuard({
    required this.wallets,
    required this.templates,
    this.notificationSources,
    this.posAccounts,
  });

  final WalletRepository wallets;
  final TransferTemplateRepository templates;
  final LocalPaymentSourceRegistry? notificationSources;
  final LocalPosAccountRegistry? posAccounts;

  Future<Result<void>> authorize(
    PaymentEvent event, {
    String? matchedTemplateId,
  }) async {
    if (event.channel == PaymentChannel.manual) return const Success(null);

    final configuredTemplates = await templates.listAll();
    if (configuredTemplates is Failure<List<TransferTemplate>>) return Failure(configuredTemplates.error);
    final allTemplates = (configuredTemplates as Success<List<TransferTemplate>>).value;

    if (event.channel == PaymentChannel.sms && posAccounts != null) {
      final posResult = await posAccounts!.findByIdentifier(event.sourceKey);
      if (posResult is Failure<PosAccount?>) return Failure(posResult.error);
      final pos = (posResult as Success<PosAccount?>).value;
      if (pos != null) {
        if (pos.status != PointOfSaleStatus.active) {
          return const Failure(AppFailure(code: 'untrusted_payment_source', message: 'Point of sale is not active'));
        }
        final posTemplates = allTemplates.where((t) => t.isActive && t.posId == pos.posId).toList(growable: false);
        if (posTemplates.isEmpty) {
          return const Failure(AppFailure(code: 'no_source_template', message: 'No active transfer template is linked to this point of sale'));
        }
        if (matchedTemplateId != null && !posTemplates.any((t) => t.id == matchedTemplateId)) {
          return const Failure(AppFailure(code: 'template_source_mismatch', message: 'Matched template is not linked to the trusted point of sale'));
        }
        return const Success(null);
      }
    }

    final listedWallets = await wallets.listAll();
    if (listedWallets is Failure<List<Wallet>>) return Failure(listedWallets.error);
    final activeWallets = (listedWallets as Success<List<Wallet>>).value
        .where((w) => w.status == WalletStatus.active)
        .toList(growable: false);

    Wallet? wallet;
    if (event.channel == PaymentChannel.sms) {
      final incomingSender = _normalize(event.sourceKey);
      // Match any active wallet whose senderId relates to the SMS origin.
      // Do not require sourceMode==sms only — operators may receive the same
      // wallet alerts over SMS short-codes even when UI mode is notification.
      wallet = activeWallets.where((w) {
        final sender = w.senderId;
        if (sender == null || sender.trim().isEmpty) return false;
        return _senderMatches(incomingSender, _normalize(sender));
      }).firstOrNull;
    } else if (event.channel == PaymentChannel.notification) {
      final package = event.packageName?.trim();
      if (package == null || package.isEmpty) {
        return const Failure(AppFailure(
          code: 'untrusted_payment_source',
          message: 'Notification source is not configured',
        ));
      }
      // Notification packages are explicit trusted sources in their own
      // registry; sourceMode remains a UI/default preference and must not block
      // a wallet that has a configured notification package.
      wallet = activeWallets.where((w) =>
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

  bool _senderMatches(String incoming, String configured) {
    if (incoming.isEmpty || configured.isEmpty) return false;
    if (incoming == configured) return true;
    if (incoming.contains(configured) || configured.contains(incoming)) {
      return true;
    }
    final incDigits = incoming.replaceAll(RegExp(r'[^0-9]'), '');
    final cfgDigits = configured.replaceAll(RegExp(r'[^0-9]'), '');
    if (incDigits.length >= 4 && cfgDigits.length >= 4) {
      if (incDigits.endsWith(cfgDigits) || cfgDigits.endsWith(incDigits)) {
        return true;
      }
    }
    return false;
  }

  String _normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
