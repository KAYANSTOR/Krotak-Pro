import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import 'local_catalog_services.dart';

/// Approves an unknown inbound sender as a payment wallet.
///
/// Used from the rejected-messages screen so the operator does not have to
/// recreate the wallet by hand after [PaymentSourceGuard] rejects
/// `untrusted_payment_source`.
final class TrustUnknownPaymentSourceService {
  const TrustUnknownPaymentSourceService({
    required this.walletCatalog,
    required this.wallets,
    required this.templates,
    required this.messages,
    required this.auditLogs,
    required this.clock,
    required this.ids,
  });

  final LocalWalletCatalogService walletCatalog;
  final WalletRepository wallets;
  final TransferTemplateRepository templates;
  final MessageRepository messages;
  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;

  Future<Result<Wallet>> approve({
    required IncomingMessage message,
    String? walletName,
  }) async {
    final sender = message.sender.trim();
    if (sender.isEmpty) {
      return const Failure(
        AppFailure(code: 'missing_sender', message: 'لا يوجد رقم مرسل لاعتماده'),
      );
    }

    final existing = await wallets.listAll();
    if (existing is Failure<List<Wallet>>) return Failure(existing.error);
    for (final w in (existing as Success<List<Wallet>>).value) {
      final sid = (w.senderId ?? '').trim();
      if (sid.isNotEmpty && sid.toUpperCase() == sender.toUpperCase()) {
        if (w.status != WalletStatus.active) {
          return const Failure(
            AppFailure(
              code: 'source_suspended',
              message: 'المصدر موجود لكنه غير نشط — فعّله من شاشة المحافظ',
            ),
          );
        }
        await _audit(message.id, w.id, reused: true);
        return Success(w);
      }
    }

    final created = await walletCatalog.saveWallet(
      name: (walletName ?? sender).trim(),
      senderId: sender,
    );
    if (created is Failure<Wallet>) return Failure(created.error);
    final wallet = (created as Success<Wallet>).value;

    final sample = message.body.trim();
    if (sample.isNotEmpty) {
      await templates.save(
        TransferTemplate(
          id: ids.next('tpl'),
          name: 'قالب أولي — $sender',
          pattern: sample,
          isActive: false,
          walletId: wallet.id,
          sampleBody: sample,
          senderCode: sender,
          requireReference: true,
        ),
      );
    }

    await _audit(message.id, wallet.id, reused: false);
    return Success(wallet);
  }

  Future<void> _audit(String messageId, String walletId, {required bool reused}) async {
    await auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: 'message',
        entityId: messageId,
        action: 'payment_source_trusted',
        occurredAt: clock.now(),
        payloadJson:
            '{"walletId":"$walletId","reused":${reused ? 'true' : 'false'}}',
      ),
    );
  }
}
