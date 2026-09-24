import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

enum MessageListCategory { rejected, failed }

class MessageListQuery {
  const MessageListQuery({required this.category, this.since});

  final MessageListCategory category;
  final DateTime? since;
}

abstract interface class MessagesSource {
  Future<Result<List<IncomingMessage>>> fetch(MessageListQuery query);
}

/// The one read path used by both dashboard counts and detail lists.
final class RepositoryMessagesSource implements MessagesSource {
  const RepositoryMessagesSource(this.messages);

  final MessageRepository messages;

  @override
  Future<Result<List<IncomingMessage>>> fetch(MessageListQuery query) async {
    final statuses = query.category == MessageListCategory.rejected
        ? const [MessageProcessingStatus.rejected]
        : const [
            MessageProcessingStatus.failed,
            MessageProcessingStatus.failedMaxAttempts,
          ];
    final all = <IncomingMessage>[];
    for (final status in statuses) {
      final result = await messages.listByStatus(status);
      if (result is Failure<List<IncomingMessage>>) return Failure(result.error);
      all.addAll((result as Success<List<IncomingMessage>>).value);
    }
    final since = query.since;
    if (since != null) {
      all.removeWhere((message) => message.receivedAt.isBefore(since));
    }
    all.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return Success(List.unmodifiable(all));
  }
}

final class MessagesFacade {
  MessagesFacade(this.source);

  final MessagesSource source;

  Future<int> count(MessageListCategory category, {DateTime? since}) async {
    final result = await source.fetch(
      MessageListQuery(category: category, since: since),
    );
    if (result is Failure<List<IncomingMessage>>) return 0;
    return (result as Success<List<IncomingMessage>>).value.length;
  }

  Future<Result<List<IncomingMessage>>> list(
    MessageListCategory category, {
    DateTime? since,
  }) {
    return source.fetch(MessageListQuery(category: category, since: since));
  }
}
