import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../rejection_codes.dart';
import '../repositories/repositories.dart';
import 'local_payment_source_registry.dart';
import 'local_pos_account_registry.dart';


/// Diagnostic evidence for a payment-source decision. Logical authorization
/// failures remain data so the rejected-message UI can explain the exact stage.
final class PaymentSourceDiagnosis {
  const PaymentSourceDiagnosis({
    required this.channel,
    required this.rawSource,
    required this.normalizedSource,
    required this.packageName,
    required this.authorized,
    required this.activeTemplateIds,
    required this.sourceEnabled,
    this.walletId,
    this.walletName,
    this.walletStatus,
    this.walletSourceMode,
    this.posId,
    this.posName,
    this.posStatus,
    this.matchedTemplateId,
    this.matchedTemplateName,
    this.matchedTemplateWalletId,
    this.matchedTemplatePosId,
    this.failureCode,
    this.failureMessage,
  });

  final PaymentChannel channel;
  final String rawSource;
  final String normalizedSource;
  final String? packageName;
  final bool authorized;
  final List<String> activeTemplateIds;
  final bool sourceEnabled;
  final String? walletId;
  final String? walletName;
  final WalletStatus? walletStatus;
  final WalletSourceMode? walletSourceMode;
  final String? posId;
  final String? posName;
  final PointOfSaleStatus? posStatus;
  final String? matchedTemplateId;
  final String? matchedTemplateName;
  final String? matchedTemplateWalletId;
  final String? matchedTemplatePosId;
  final String? failureCode;
  final String? failureMessage;

  Map<String, Object?> toJson() => {
        'channel': channel.name,
        'rawSource': rawSource,
        'normalizedSource': normalizedSource,
        'packageName': packageName,
        'authorized': authorized,
        'sourceEnabled': sourceEnabled,
        'walletId': walletId,
        'walletName': walletName,
        'walletStatus': walletStatus?.name,
        'walletSourceMode': walletSourceMode?.name,
        'posId': posId,
        'posName': posName,
        'posStatus': posStatus?.name,
        'activeTemplateIds': activeTemplateIds,
        'matchedTemplateId': matchedTemplateId,
        'matchedTemplateName': matchedTemplateName,
        'matchedTemplateWalletId': matchedTemplateWalletId,
        'matchedTemplatePosId': matchedTemplatePosId,
        'failureCode': failureCode,
        'failureMessage': failureMessage,
      };
}

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

  Future<Result<PaymentSourceDiagnosis>> diagnose(
    PaymentEvent event, {
    String? matchedTemplateId,
  }) async {
    final auth = await authorize(event, matchedTemplateId: matchedTemplateId);
    final configured = await templates.listAll();
    if (configured is Failure<List<TransferTemplate>>) return Failure(configured.error);
    final allTemplates = (configured as Success<List<TransferTemplate>>).value;

    if (event.channel == PaymentChannel.manual) {
      return Success(PaymentSourceDiagnosis(
        channel: event.channel,
        rawSource: event.sourceKey,
        normalizedSource: _normalize(event.sourceKey),
        packageName: event.packageName?.trim(),
        authorized: true,
        activeTemplateIds: allTemplates
            .where((t) => t.isActive)
            .map((t) => t.id)
            .toList(growable: false),
        sourceEnabled: true,
        matchedTemplateId: matchedTemplateId,
        matchedTemplateName: matchedTemplateId == null
            ? null
            : allTemplates.where((t) => t.id == matchedTemplateId).firstOrNull?.name,
      ));
    }

    Wallet? wallet;
    PosAccount? pos;
    var sourceEnabled = true;
    List<TransferTemplate> sourceTemplates = const [];

    if (event.channel == PaymentChannel.sms && posAccounts != null) {
      final result = await posAccounts!.findByIdentifier(event.sourceKey);
      if (result is Failure<PosAccount?>) return Failure(result.error);
      pos = (result as Success<PosAccount?>).value;
      if (pos != null && pos.status == PointOfSaleStatus.active) {
        sourceTemplates = allTemplates.where((t) => t.isActive && t.posId == pos!.posId).toList(growable: false);
      }
    }

    if (pos == null) {
      final listed = await wallets.listAll();
      if (listed is Failure<List<Wallet>>) return Failure(listed.error);
      final active = (listed as Success<List<Wallet>>).value.where((w) => w.status == WalletStatus.active).toList(growable: false);
      if (event.channel == PaymentChannel.sms) {
        wallet = active.where((w) {
          final sender = w.senderId?.trim();
          if (sender == null || sender.isEmpty) return false;
          return _senderMatches(_normalize(event.sourceKey), _normalize(sender));
        }).firstOrNull;
      } else if (event.channel == PaymentChannel.notification) {
        final packageName = event.packageName?.trim();
        if (packageName != null && packageName.isNotEmpty) {
          wallet = active.where((w) =>
              w.sourceMode == WalletSourceMode.notification &&
              w.packageName?.trim() == packageName).firstOrNull;
          if (wallet != null && notificationSources != null) {
            final sources = await notificationSources!.list();
            if (sources is Failure<List<PaymentSource>>) return Failure(sources.error);
            sourceEnabled = (sources as Success<List<PaymentSource>>).value.any(
              (source) => source.packageName == packageName && source.enabled,
            );
          }
        }
      }
      if (wallet != null && sourceEnabled) {
        sourceTemplates = allTemplates
            .where((t) => t.isActive && _belongsToWallet(t, wallet!))
            .toList(growable: false);
      }
    }

    final matched = matchedTemplateId == null
        ? null
        : allTemplates.where((t) => t.id == matchedTemplateId).firstOrNull;
    final error = auth is Failure<void> ? auth.error : null;
    return Success(PaymentSourceDiagnosis(
      channel: event.channel,
      rawSource: event.sourceKey,
      normalizedSource: _normalize(event.sourceKey),
      packageName: event.packageName?.trim(),
      authorized: auth is Success<void>,
      activeTemplateIds: sourceTemplates.map((t) => t.id).toList(growable: false),
      sourceEnabled: sourceEnabled,
      walletId: wallet?.id,
      walletName: wallet?.name,
      walletStatus: wallet?.status,
      walletSourceMode: wallet?.sourceMode,
      posId: pos?.posId,
      posName: pos?.name,
      posStatus: pos?.status,
      matchedTemplateId: matched?.id,
      matchedTemplateName: matched?.name,
      matchedTemplateWalletId: matched?.walletId,
      matchedTemplatePosId: matched?.posId,
      failureCode: error?.code,
      failureMessage: error?.message,
    ));
  }

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
          return const Failure(AppFailure(code: RejectionCodes.unknownSender, message: 'Point of sale is not active'));
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
          code: RejectionCodes.unknownSender,
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
        code: RejectionCodes.unknownSender,
        message: 'Payment source is not linked to an active configured wallet',
      ));
    }

    final liveTemplates = (configuredTemplates as Success<List<TransferTemplate>>).value
        .where((t) => t.isActive && _belongsToWallet(t, wallet))
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

  /// Older installations stored wallet templates with only senderCode. Keep
  /// those templates source-scoped, but allow them to follow the verified SMS
  /// sender instead of treating an active, valid template as unrelated.
  bool _belongsToWallet(TransferTemplate template, Wallet wallet) {
    if (template.walletId?.trim() == wallet.id) return true;
    if (wallet.sourceMode != WalletSourceMode.sms) return false;
    final senderCode = template.senderCode?.trim();
    final senderId = wallet.senderId?.trim();
    if (senderCode == null || senderCode.isEmpty || senderId == null || senderId.isEmpty) {
      return false;
    }
    return _senderMatches(_normalize(senderCode), _normalize(senderId));
  }

  String _normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
