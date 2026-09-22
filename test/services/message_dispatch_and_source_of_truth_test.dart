import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/messages_source_of_truth.dart';
import 'package:net_app/domain/services/outbound_message_dispatch_guard.dart';

final class _ClaimStore implements OutboundMessageStore {
  bool claimed = false;

  @override
  Future<bool> claimForDispatch(
    String messageId, {
    required DateTime now,
    required DateTime staleBefore,
  }) async {
    if (claimed) return false;
    claimed = true;
    return true;
  }
}

final class _Messages implements MessageRepository {
  final values = <String, IncomingMessage>{};

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    values[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async => Success(values[id]);
  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async => const Success(null);
  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async => Success(values.values.toList());
  @override
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async =>
      Success(values.values.where((message) => message.status == status).toList());
  @override
  Future<Result<int>> countByStatus(MessageProcessingStatus status) async =>
      Success(values.values.where((message) => message.status == status).length);
  @override
  Stream<int> watchCountByStatus(MessageProcessingStatus status) async* {
    yield values.values.where((message) => message.status == status).length;
  }
  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(values.values.take(limit).toList());
  @override
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async => const Success(null);
  @override
  Future<Result<void>> delete(String id) async => const Success(null);
}

void main() {
  test('concurrent dispatch passes send a claimed message only once', () async {
    final store = _ClaimStore();
    final guard = OutboundMessageDispatchGuard(store: store);
    final message = IncomingMessage(
      id: 'm1',
      sender: 'sender',
      body: 'body',
      receivedAt: DateTime.utc(2026, 9, 23),
      status: MessageProcessingStatus.pending,
    );
    var sends = 0;
    Future<void> send() async {
      sends++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    await Future.wait([
      guard.runOnce(message, send),
      guard.runOnce(message, send),
    ]);

    expect(sends, 1);
  });

  test('failed source returns retryable and exhausted messages to the same list', () async {
    final messages = _Messages();
    await messages.save(IncomingMessage(
      id: 'retryable',
      sender: 'sender',
      body: 'body',
      receivedAt: DateTime.utc(2026, 9, 23),
      status: MessageProcessingStatus.failed,
    ));
    await messages.save(IncomingMessage(
      id: 'exhausted',
      sender: 'sender',
      body: 'body',
      receivedAt: DateTime.utc(2026, 9, 22),
      status: MessageProcessingStatus.failedMaxAttempts,
    ));

    final facade = MessagesFacade(RepositoryMessagesSource(messages));
    final listed = await facade.list(MessageListCategory.failed);

    expect(listed, isA<Success<List<IncomingMessage>>>());
    final rows = (listed as Success<List<IncomingMessage>>).value;
    expect(await facade.count(MessageListCategory.failed), rows.length);
    expect(rows.map((row) => row.id), containsAll(<String>['retryable', 'exhausted']));
  });
}
