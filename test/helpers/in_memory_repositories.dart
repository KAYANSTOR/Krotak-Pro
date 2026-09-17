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
            m.status == MessageProcessingStatus.pending)
        .toList();
    return Success(list);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async {
    return Success(_byId.values.where((m) => m.status == status).toList());
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
}

final class InMemoryAuditLogRepository implements AuditLogRepository {
  final List<AuditLog> logs = [];

  @override
  Future<Result<void>> append(AuditLog log) async {
    logs.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async {
    return Success(
      logs.where((l) => l.entityType == entityType && l.entityId == entityId).toList(),
    );
  }
}

final class InMemoryUnitOfWork implements UnitOfWork {
  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}
