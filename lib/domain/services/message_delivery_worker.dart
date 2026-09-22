import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';
import 'local_message_retry_service.dart';
import 'message_retry_policy.dart';
import 'message_pipeline_trace.dart';
import 'services.dart';
import 'outbound_template_renderer.dart';

/// Phase 4 delivery worker: resend voucher SMS for already-committed sales.
///
/// Rules (screenshots + Phase 3):
/// - Only messages with `voucher_committed` and without `sms_delivery_succeeded`
/// - Never issues a second card; uses the same cardId from the audit payload
/// - Respects [MessageRetryPolicy] (max 3 attempts, exponential backoff)
/// - Stuck `sending` / `pending` older than [MessageRetryPolicy.confirmPendingTimeout]
///   (15 minutes) are treated as due for another delivery attempt
final class MessageDeliveryWorker {
  MessageDeliveryWorker({
    required this.messages,
    required this.auditLogs,
    required this.cards,
    required this.messageSender,
    required this.retryService,
    required this.clock,
    required this.ids,
    this.policy = const MessageRetryPolicy(),
    this.metrics,
    this.settings,
  });