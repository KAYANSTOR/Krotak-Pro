import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'local_message_recovery_service.dart';
import 'local_message_retry_service.dart';

/// عمليات التدخل اليدوي على الرسائل الفاشلة/المعلّقة — 1.0.9.
final class PendingOperationsService {
  const PendingOperationsService({
    required this.messages,
    required this.retryService,
    required this.recoveryService,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final MessageRepository messages;
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
    for (final m in (listed as Success<List<IncomingMessage>>).value) {
      final st = await retryService.state(m.id);
      if (st is Failure<MessageRetryState>) continue;
      final state = (st as Success<MessageRetryState>).value;
      if (!state.exhausted && state.attempts == 0) continue;
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
}
