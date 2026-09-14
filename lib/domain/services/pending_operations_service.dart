import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_message_recovery_service.dart';
import 'local_message_retry_service.dart';
import 'services.dart';

/// عمليات التدخل اليدوي على الرسائل الفاشلة/المعلّقة — 1.0.9.
///
/// - Bulk reset & retry
/// - تأكيد تسليم يدوي (بدون إعادة إرسال)
/// - إلغاء حجز وإعادة الكرت للمخزون مع حماية مالية
final class PendingOperationsService {
  const PendingOperationsService({
    required this.messages,
    required this.sales,
    required this.cards,
    required this.transactions,
    required this.auditLogs,
    required this.retryService,
    required this.recoveryService,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final MessageRepository messages;
  final SaleRepository sales;
  final CardRepository cards;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final LocalMessageRetryService retryService;
  final LocalMessageRecoveryService recoveryService;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  /// يعيد جدولة كل الرسائل الفاشلة المستنفدة دفعة واحدة.
  Future<Result<int>> bulkResetAndRetry() async {
    final listed = await messages.listByStatus(MessageProcessingStatus.failed);
    if (listed is Failure<List<IncomingMessage>>) return Failure(listed.error);
    var count = 0;
    for (final m in listed.value) {
      final st = await retryService.state(m.id);
      if (st is Failure<MessageRetryState>) continue;
      final state = (st as Success<MessageRetryState>).value;
      if (!state.exhausted && state.attempts == 0) continue;
      // مسح حالة الاستنفاد وطلب إعادة فورية
      await retryService.clearAfterSuccess(m.id);
      await retryService.requestImmediateRetry(m.id);
      await messages.updateStatus(m.id, MessageProcessingStatus.received);
      count++;
    }
    if (count > 0) {
      await recoveryService.recoverPending();
    }
    return Success(count);
  }

  /// تأكيد أن الكرت وصل للعميل يدويًا — يغلق العملية دون إرسال SMS جديد.
  Future<Result<void>> confirmManualDelivery({
    required String messageId,
    String? note,
  }) {
    return unitOfWork.run(() async {
      final found = await messages.findById(messageId);
      if (found is Failure<IncomingMessage?>) return Failure(found.error);
      final msg = (found as Success<IncomingMessage?>).value;
      if (msg == null) {
        return const Failure(
          AppFailure(code: 'message_not_found', message: 'الرسالة غير موجودة'),
        );
      }
      final updated = await messages.updateStatus(
        messageId,
        MessageProcessingStatus.processed,
      );
      if (updated is Failure<void>) return Failure(updated.error);
      await retryService.clearAfterSuccess(messageId);
      return auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: messageId,
          action: 'manual_delivery_confirmed',
          payloadJson: note == null ? null : '{"note":"$note"}',
          occurredAt: clock.now(),
        ),
      );
    });
  }

  /// إلغاء حجز كرت مرتبط بعملية فاشلة وإعادته للمخزون + عكس قيد البيع إن وُجد.
  Future<Result<void>> releaseVoucherAndRollback({
    required String saleId,
  }) {
    return unitOfWork.run(() async {
      final found = await sales.findById(saleId);
      if (found is Failure<Sale?>) return Failure(found.error);
      final sale = (found as Success<Sale?>).value;
      if (sale == null) {
        return const Failure(
          AppFailure(code: 'sale_not_found', message: 'عملية البيع غير موجودة'),
        );
      }
      if (sale.status == TransactionStatus.reversed) {
        return const Success(null);
      }

      // إعادة الكرت للمخزون
      final restored = await cards.restoreAvailable(sale.cardId);
      if (restored is Failure<void>) return Failure(restored.error);

      // قيد عكسي في الدفتر
      final now = clock.now();
      final reversal = Transaction(
        id: ids.next('txn'),
        type: TransactionType.reversal,
        status: TransactionStatus.completed,
        amount: sale.amount,
        createdAt: now,
        customerId: sale.customerId,
        reference: 'release:${sale.id}',
      );
      final appended = await transactions.append(reversal);
      if (appended is Failure<void>) return Failure(appended.error);

      final reversed = Sale(
        id: sale.id,
        customerId: sale.customerId,
        cardId: sale.cardId,
        amount: sale.amount,
        status: TransactionStatus.reversed,
        createdAt: sale.createdAt,
      );
      final saved = await sales.save(reversed);
      if (saved is Failure<void>) return Failure(saved.error);

      return auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'sale',
          entityId: sale.id,
          action: 'voucher_released_rollback',
          occurredAt: now,
          payloadJson: '{"cardId":"${sale.cardId}","customerId":"${sale.customerId}"}',
        ),
      );
    });
  }
}
