final class AuditLog {
  const AuditLog({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.occurredAt,
    this.payloadJson,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String action;
  final DateTime occurredAt;
  final String? payloadJson;
}
