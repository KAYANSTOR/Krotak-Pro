import '../../core/result.dart';
import 'local_pos_account_registry.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/pos_account.dart';
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
    this.posRegistry,
  });

  final WalletRepository wallets;
  final TransferTemplateRepository templates;
  final LocalPaymentSourceRegistry? notificationSources;
  final LocalPosAccountRegistry? posRegistry;

  Future<Result<PaymentSourceScope>> resolve(PaymentEvent event) async {
    if (event.channel == PaymentChannel.manual) {
      return const Failure(
        AppFailure(
          code: 'manual_scope_not_required',
          message: 'Manual events do not require an inbound source scope',
        ),
      );
    }

    final listedWallets = await wallets.listAll();
    if (listedWallets is Failure<List<Wallet>>) return Failure(listedWallets.error);
    final activeWallets = (listedWallets as Success<List<Wallet>>).value
        .where((w) => w.status == WalletStatus.active)
        .toList(growable: false);

    final matchingWallets = <Wallet>[];
    if (event.channel == PaymentChannel.sms) {
      final incomingSender = _normalize(event.sourceKey);
      matchingWallets.addAll(
        activeWallets.where((w) {
          if (w.sourceMode != WalletSourceMode.sms) return false;
          final sender = w.senderId;
          return sender != null &&
              sender.trim().isNotEmpty &&
              _normalize(sender) == incomingSender;
        }),
      );
    } else if (event.channel == PaymentChannel.notification) {
      final package = event.packageName?.trim();
      if (package == null || package.isEmpty) {
        return const Failure(
          AppFailure(
            code: 'untrusted_payment_source',
            message: 'Notification source is not configured',
          ),
        );
      }
      matchingWallets.addAll(
        activeWallets.where((w) =>
            w.sourceMode == WalletSourceMode.notification &&
            w.packageName != null &&
            w.packageName!.trim() == package),
      );
      if (matchingWallets.isNotEmpty && notificationSources != null) {
        final configured = await notificationSources!.list();
        if (configured is Failure<List<PaymentSource>>) {
          return Failure(configured.error);
        }
        final source = (configured as Success<List<PaymentSource>>).value
            .where((s) => s.packageName == package && s.enabled)
            .firstOrNull;
        if (source == null) matchingWallets.clear();
      }
    }

    if (matchingWallets.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'untrusted_payment_source',
          message: 'Payment source is not linked to an active configured wallet',
        ),
      );
    }
    if (matchingWallets.length > 1) {
      return const Failure(
        AppFailure(
          code: 'payment_source_ambiguous',
          message: 'Payment source is linked to more than one active wallet',
        ),
      );
    }
    final wallet = matchingWallets.single;

    final configuredTemplates = await templates.listAll();
    if (configuredTemplates is Failure<List<TransferTemplate>>) {
      return Failure(configuredTemplates.error);
    }

    final allLive = (configuredTemplates as Success<List<TransferTemplate>>).value
        .where((t) => t.isActive && t.walletId == wallet.id)
        .toList(growable: false);

    PosAccount? pos;
    final registry = posRegistry;
    if (registry != null) {
      final posResult = await registry.findByMessage(
        sender: event.sourceKey,
        body: event.body,
      );
      if (posResult is Failure<PosAccount?>) return Failure(posResult.error);
      pos = (posResult as Success<PosAccount?>).value;
    }

    final scopedTemplates = pos == null
        ? allLive.where((t) => t.posAccountId == null).toList(growable: false)
        : allLive.where((t) => t.posAccountId == pos.posId).toList(growable: false);

    return Success(
      PaymentSourceScope(
        wallet: wallet,
        posAccount: pos,
        templates: scopedTemplates,
      ),
    );
  }

  Future<Result<void>> authorize(
    PaymentEvent event, {
    String? matchedTemplateId,
  }) async {
    if (event.channel == PaymentChannel.manual) return const Success(null);

    final scopeResult = await resolve(event);
    if (scopeResult is Failure<PaymentSourceScope>) {
      return Failure(scopeResult.error);
    }
    final scope = (scopeResult as Success<PaymentSourceScope>).value;
    if (scope.templates.isEmpty) {
      return Failure(
        AppFailure(
          code: scope.posAccount == null
              ? 'no_source_template'
              : 'pos_no_active_template',
          message: scope.posAccount == null
              ? 'No active transfer template is linked to this payment source'
              : 'No active transfer template is configured for this POS account',
        ),
      );
    }

    if (matchedTemplateId != null &&
        !scope.templates.any((t) => t.id == matchedTemplateId)) {
      return const Failure(
        AppFailure(
          code: 'template_source_mismatch',
          message: 'Matched template is outside the trusted source scope',
        ),
      );
    }
    return const Success(null);
  }

  String _normalize(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

final class PaymentSourceScope {
  const PaymentSourceScope({
    required this.wallet,
    required this.templates,
    this.posAccount,
  });

  final Wallet wallet;
  final PosAccount? posAccount;
  final List<TransferTemplate> templates;

  bool get isPos => posAccount != null;
}
