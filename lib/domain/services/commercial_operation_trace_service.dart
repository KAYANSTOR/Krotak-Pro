import 'dart:convert';

import '../entities/audit.dart';
import '../repositories/repositories.dart';
import '../../core/result.dart';

/// Phase 16 — reconstruct a commercial operation from audit rows.
///
/// A lookup by operation id, card id, customer id, message id, or phone
/// returns the related audit events plus extracted linkage fields so an
/// operator can answer: who / when / what / which card / which message /
/// send result.
final class CommercialOperationTrace {
  const CommercialOperationTrace({
    required this.query,
    required this.events,
    required this.operationIds,
    required this.customerIds,
    required this.cardIds,
    required this.messageIds,
    required this.actions,
  });

  final String query;
  final List<AuditLog> events;
  final Set<String> operationIds;
  final Set<String> customerIds;
  final Set<String> cardIds;
  final Set<String> messageIds;
  final Set<String> actions;

  bool get isEmpty => events.isEmpty;
}

final class CommercialOperationTraceService {
  const CommercialOperationTraceService(this.auditLogs);

  final AuditLogRepository auditLogs;

  Future<Result<CommercialOperationTrace>> lookup(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return Success(
        CommercialOperationTrace(
          query: query,
          events: const [],
          operationIds: const {},
          customerIds: const {},
          cardIds: const {},
          messageIds: const {},
          actions: const {},
        ),
      );
    }
    final found = await auditLogs.search(query: query);
    if (found is Failure<List<AuditLog>>) {
      return Failure(found.error);
    }
    final events = (found as Success<List<AuditLog>>).value;
    final operationIds = <String>{};
    final customerIds = <String>{};
    final cardIds = <String>{};
    final messageIds = <String>{};
    final actions = <String>{};
    for (final event in events) {
      actions.add(event.action);
      if (event.entityType == 'message') {
        messageIds.add(event.entityId);
      }
      if (event.entityType == 'card') {
        cardIds.add(event.entityId);
      }
      if (event.entityType == 'customer') {
        customerIds.add(event.entityId);
      }
      final payload = _decode(event.payloadJson);
      _add(operationIds, payload['operationId'] ?? payload['saleOperationId']);
      _add(customerIds, payload['customerId']);
      _add(cardIds, payload['cardId']);
      _add(messageIds, payload['messageId']);
    }
    return Success(
      CommercialOperationTrace(
        query: query,
        events: events,
        operationIds: operationIds,
        customerIds: customerIds,
        cardIds: cardIds,
        messageIds: messageIds,
        actions: actions,
      ),
    );
  }

  static Map<String, Object?> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return const {};
  }

  static void _add(Set<String> target, Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isNotEmpty) target.add(text);
  }
}
