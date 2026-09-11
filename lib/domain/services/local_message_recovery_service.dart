import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'services.dart';

/// Replays pending / parsed messages through [TransferProcessor].
///
/// Recovery guarantees:
/// - already processed messages are skipped (processor / external ref)
/// - rejected messages are not re-run unless status reset externally
/// - each message is attempted independently; one failure does not stop the batch
final class LocalMessageRecoveryService {
  const LocalMessageRecoveryService({
    required this.messages,
    required this.parser,
    required this.processor,
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;

  Future<Result<MessageRecoveryReport>> recoverPending() async {
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

      final parseResult = parser.parse(message);
      if (parseResult is Failure<ParsedTransfer>) {
        await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
        failed++;
        errors.add('${message.id}:${parseResult.error.code}');
        continue;
      }

      final parsed = (parseResult as Success<ParsedTransfer>).value;
      await messages.updateStatus(message.id, MessageProcessingStatus.parsed);

      final processResult = await processor.process(parsed);
      if (processResult is Success<Transaction>) {
        processed++;
      } else {
        failed++;
        errors.add('${message.id}:${(processResult as Failure<Transaction>).error.code}');
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
}

final class MessageRecoveryReport {
  const MessageRecoveryReport({
    required this.attempted,
    required this.processed,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int attempted;
  final int processed;
  final int skipped;
  final int failed;
  final List<String> errors;
}
