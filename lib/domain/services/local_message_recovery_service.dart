import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'services.dart';

/// Replays pending / parsed messages through [TransferProcessor].
///
/// Recovery guarantees:
/// - already processed messages are skipped (processor / external ref)
/// - rejected messages are not re-run unless status reset externally
/// - each message is attempted independently; one failure does not stop the batch
/// - PD-07: gated by [SettingKeys.processOldMessagesOnResume] (default ON)
/// - unmatched amounts under category-only stay [MessageProcessingStatus.parsed]
///   and are re-attempted only if categories later match; otherwise remain pending
final class LocalMessageRecoveryService {
  const LocalMessageRecoveryService({
    required this.messages,
    required this.parser,
    required this.processor,
    this.settings,
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final SettingsRepository? settings;

  Future<Result<MessageRecoveryReport>> recoverPending() async {
    final enabled = await _processOldMessagesOnResume();
    if (!enabled) {
      return const Success(
        MessageRecoveryReport(
          attempted: 0,
          processed: 0,
          skipped: 0,
          failed: 0,
          errors: <String>[],
          skippedBySetting: true,
        ),
      );
    }

    final pending = await messages.pendingProcessing();
    if (pending is Failure<List<IncomingMessage>>) {
      return Failure(pending.error);
    }

    final list = (pending as Success<List<IncomingMessage>>).value;
    var processed = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (final message in list) {
      if (message.status == MessageProcessingStatus.processed) {
        skipped++;
        continue;
      }
      if (message.status == MessageProcessingStatus.rejected) {
        skipped++;
        continue;
      }

      final parseResult = parser.parse(message);
      if (parseResult is Failure<ParsedTransfer>) {
        await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
        failed++;
        errors.add('${message.id}:${parseResult.error.code}');
        continue;
      }

      final parsed = (parseResult as Success<ParsedTransfer>).value;
      if (message.status != MessageProcessingStatus.parsed) {
        await messages.updateStatus(message.id, MessageProcessingStatus.parsed);
      }

      final processResult = await processor.process(parsed);
      if (processResult is Success<Transaction>) {
        processed++;
      } else {
        final code = (processResult as Failure<Transaction>).error.code;
        // Unmatched pending is expected operator work — count as skipped, not failed.
        if (code == 'unmatched_amount_pending') {
          skipped++;
        } else {
          failed++;
          errors.add('${message.id}:$code');
        }
      }
    }

    return Success(
      MessageRecoveryReport(
        attempted: list.length,
        processed: processed,
        skipped: skipped,
        failed: failed,
        errors: errors,
      ),
    );
  }

  Future<bool> _processOldMessagesOnResume() async {
    final s = settings;
    if (s == null) return SettingDefaults.processOldMessagesOnResume;
    final result = await s.find(SettingKeys.processOldMessagesOnResume);
    if (result is! Success<AppSetting?>) {
      return SettingDefaults.processOldMessagesOnResume;
    }
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

  /// True when [SettingKeys.processOldMessagesOnResume] is OFF.
  final bool skippedBySetting;
}
