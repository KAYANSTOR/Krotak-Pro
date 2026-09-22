import 'package:net_app/core/result.dart';
import 'package:net_app/domain/domain.dart';

/// Shared in-memory fakes that implement the frozen repository contracts.
/// Prefer these over one-off fakes in new tests (Phase 1 contracts rule).

final class InMemoryMessageRepository implements MessageRepository {
  final Map<String, IncomingMessage> _byId = {};

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    _byId[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(_byId[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async {
    for (final m in _byId.values) {
      if (m.externalReference == reference) return Success(m);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async {
    final list = _byId.values
        .where((m) =>
            m.status == MessageProcessingStatus.received ||
            m.status == MessageProcessingStatus.parsed ||
            m.status == MessageProcessingStatus.pending ||
            m.status == MessageProcessingStatus.sending ||
            m.status == MessageProcessingStatus.failed)
        .toList();
    return Success(list);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async {
    return Success(_byId.values.where((m) => m.status == status).toList());
  }

  @override
  Future<Result<int>> countByStatus(MessageProcessingStatus status) async =>
      Success(_byId.values.where((m) => m.status == status).length);

  @override
  Stream<int> watchCountByStatus(MessageProcessingStatus status) async* {
    final r = await countByStatus(status);
    yield r is Success<int> ? r.value : 0;
  }

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async {
    final list = _byId.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return Success(list.take(limit).toList());
  }

  @override
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async {
    final current = _byId[id];
    if (current == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'message not found'));
    }
    _byId[id] = IncomingMessage(
      id: current.id,
      sender: current.sender,
      body: current.body,
      receivedAt: current.receivedAt,
      status: status,
      externalReference: current.externalReference,
      customerIdentifier: current.customerIdentifier,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    _byId.remove(id);
    return const Success(null);
  }
}
