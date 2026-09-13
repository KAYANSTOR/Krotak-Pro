import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'local_message_retry_service.dart';
import 'services.dart';

/// Phase 4 recovery coordinator for received, parsed and failed messages.
///
/// Recovery is idempotent and bounded by [LocalMessageRetryService]. A
/// transient processor failure is scheduled with exponential backoff; terminal
/// business failures remain rejected/parsed for operator handling.
final class LocalMessageRecoveryService {
  const LocalMessageRecoveryService({
    required this.messages,
    required this.parser,
    required this.processor,
    required this.retryService,
    this.settings,
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final LocalMessageRetryService retryService;
  final SettingsRepository? settings;

  Future<Result<MessageRecoveryReport>> recoverPending() async {
    final enabled = await _processOldMessagesOnResume();
    if (!enabled) {
      return const Success(MessageRecoveryReport(
        attempted: 0,
        processed: 0,
        skipped: 0,
        failed: 0,
        errors: <String>[],
        skippedBySetting: true,
      ));
    }

    final pending = await messages.pendingProcessing();
    if (pending is Failure<List<IncomingMessage>>) return Failure(pending.error);
    final list = (pending as Success<List<IncomingMessage>>).value;
    var attempted = 0;
    var processed = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (final message in list) {
      final due = await retryService.isDue(message.id);
      if (!due) {
        skipped++;
        continue;
      }

      attempted++;
      if (message.status == MessageProcessingStatus.received) {
        final parseResult = parser.parse(message);
        if (parseResult is Failure<ParsedTransfer>) {
          await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
          failed++;
          errors.add('${message.id}:${parseResult.error.code}');
          continue;
        }
        await messages.updateStatus(message.id, MessageProcessingStatus.parsed);
      }

      final parsed = parser.parse(message);
      if (parsed is Failure<ParsedTransfer>) {
        await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
        failed++;
        errors.add('${message.id}:${parsed.error.code}');
        continue;
      }

      final result = await processor.process((parsed as Success<ParsedTransfer>).value);
      if (result is Success<Transaction>) {
        processed++;
        await retryService.clearAfterSuccess(message.id);
        continue;
      }

      final error = (result as Failure<Transaction>).error;
      if (error.code == 'unmatched_amount_pending') {
        skipped++;
        continue;
      }

      final scheduled = await retryService.recordFailure(
        messageId: message.id,
        error: error,
      );
      if (scheduled is Failure<MessageRetryState>) {
        failed++;
        errors.add('${message.id}:${scheduled.error.code}');
        continue;
      }
      final state = (scheduled as Success<MessageRetryState>).value;
      if (state.exhausted) {
        failed++;
        errors.add('${message.id}:retry_exhausted:${error.code}');
      } else {
        skipped++;
      }
    }

    return Success(MessageRecoveryReport(
      attempted: attempted,
      processed: processed,
      skipped: skipped,
      failed: failed,
      errors: List.unmodifiable(errors),
    ));
  }

  Future<Result<void>> retryNow(String messageId) async {
    final found = await messages.findById(messageId);
    if (found is Failure<IncomingMessage?>) return Failure(found.error);
    final message = (found as Success<IncomingMessage?>).value;
    if (message == null) {
      return const Failure(AppFailure(
        code: 'message_not_found',
        message: 'Message was not found',
      ));
    }
    if (message.status == MessageProcessingStatus.processed ||
        message.status == MessageProcessingStatus.rejected) {
      return const Failure(AppFailure(
        code: 'message_not_retryable',
        message: 'Message is not eligible for retry',
      ));
    }
    final request = await retryService.requestImmediateRetry(messageId);
    if (request is Failure<void>) return request;
    final recovered = await recoverPending();
    if (recovered is Failure<MessageRecoveryReport>) return Failure(recovered.error);
    final report = (recovered as Success<MessageRecoveryReport>).value;
    return report.failed > 0
        ? const Failure(AppFailure(
            code: 'retry_failed',
            message: 'Retry did not complete successfully',
          ))
        : const Success(null);
  }

  Future<bool> _processOldMessagesOnResume() async {
    final s = settings;
    if (s == null) return SettingDefaults.processOldMessagesOnResume;
    final result = await s.find(SettingKeys.processOldMessagesOnResume);
    if (result is! Success<AppSetting?>) return SettingDefaults.processOldMessagesOnResume;
    return SettingBool.read(
      result.value?.value,
      defaultValue: SettingDefaults.processOldMessagesOnResume,
    );
  }
}

final class MessageRecoveryReport {
  const MessageRecoveryReport({
    required this.attempted,
    required this.processed,
    required this.skipped,
    required this.failed,
    required this.errors,
    this.skippedBySetting = false,
  });

  final int attempted;
  final int processed;
  final int skipped;
  final int failed;
  final List<String> errors;
  final bool skippedBySetting;
}
