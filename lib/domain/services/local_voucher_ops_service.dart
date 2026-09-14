import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';

/// عمليات التدخل اليدوي على الكروت المحجوزة — تأكيد تسليم / إلغاء حجز + Rollback.
final class LocalVoucherOpsService {
  const LocalVoucherOpsService({
    required this.cards,
    required this.sales,
    required this.transactions,
    required this.balances,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CardRepository cards;
  final SaleRepository sales;
  final TransactionRepository transactions;
  final CustomerBalanceService balances;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  /// تأكيد أن الكرت سُلّم للعميل يدويًا (خارج مسار SMS).
  Future<Result<void>> confirmManualDelivery({
    required String cardId,
    required String saleId,
    String? note,
  }) {
    return unitOfWork.run(() async {
      final found = await cards.findById(cardId);
      if (found is Failure<Card?>) return Failure(found.error);
      final card = (found as Success<Card?>).value;
      if (card == null) {
        return const Failure(AppFailure(code: 'card_not_found', message: 'الكرت غير موجود'));
      }
      if (card.status == CardStatus.sold) {
        await auditLogs.append(AuditLog(
          id: ids.next('audit'),
          entityType: 'card',
          entityId: cardId,
          action: 'manual_delivery_confirmed',
          occurredAt: clock.now(),
          payloadJson: '{"saleId":"$saleId","note":"${note ?? ''}"}',
        ));
        return const Success(null);
      }
      if (card.status != CardStatus.reserved) {
        return const Failure(
          AppFailure(code: 'card_not_reserved', message: 'الكرت ليس في حالة حجز'),
        );
      }
      final marked = await cards.markSold(cardId, saleId);
      if (marked is Failure<void>) return Failure(marked.error);
      await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'card',
        entityId: cardId,
        action: 'manual_delivery_confirmed',
        occurredAt: clock.now(),
        payloadJson: '{"saleId":"$saleId","note":"${note ?? ''}"}',
      ));
      return const Success(null);
    });
  }

  /// إلغاء الحجز وإعادة الكرت للمخزون مع إرجاع المبلغ لرصيد العميل.
  Future<Result<void>> releaseReservationAndRollback({
    required String cardId,
    required String customerId,
    required Money amount,
    String? reservationId,
    String? reason,
  }) {
    return unitOfWork.run(() async {
      final found = await cards.findById(cardId);
      if (found is Failure<Card?>) return Failure(found.error);
      final card = (found as Success<Card?>).value;
      if (card == null) {
        return const Failure(AppFailure(code: 'card_not_found', message: 'الكرت غير موجود'));
      }

      if (card.status == CardStatus.reserved) {
        final rid = reservationId ?? card.reservation.reservationId;
        if (rid != null) {
          final released = await cards.releaseReservation(cardId, rid);
          if (released is Failure<void>) return Failure(released.error);
        }
      } else if (card.status == CardStatus.sold) {
        final restored = await cards.restoreAvailable(cardId);
        if (restored is Failure<void>) return Failure(restored.error);
      } else if (card.status == CardStatus.available) {
        // already free
      } else {
        return Failure(
          AppFailure(
            code: 'card_not_releasable',
            message: 'لا يمكن تحرير كرت بحالة ${card.status.name}',
          ),
        );
      }

      if (amount.minorUnits > 0) {
        final credit = await balances.credit(
          customerId: customerId,
          amount: amount,
          reference: 'voucher-rollback:$cardId:${ids.next('rb')}',
        );
        if (credit is Failure<Transaction>) return Failure(credit.error);
      }

      await auditLogs.append(AuditLog(
        id: ids.next('audit'),
        entityType: 'card',
        entityId: cardId,
        action: 'voucher_released_rollback',
        occurredAt: clock.now(),
        payloadJson:
            '{"customerId":"$customerId","amount":${amount.minorUnits},"reason":"${reason ?? 'manual_release'}"}',
      ));
      return const Success(null);
    });
  }
}
