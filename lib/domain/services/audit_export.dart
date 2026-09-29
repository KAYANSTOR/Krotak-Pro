import '../entities/audit.dart';

/// يحوّل سجل التدقيق إلى CSV UTF-8 مع BOM حتى تفتحه Excel بالعربية.
String buildAuditCsv(List<AuditLog> logs) {
  final buf = StringBuffer()
    ..write('\uFEFF')
    ..writeln('id,occurred_at,action,entity_type,entity_id,payload');
  for (final log in logs) {
    buf.writeln(
      [
        _csv(log.id),
        _csv(log.occurredAt.toIso8601String()),
        _csv(log.action),
        _csv(log.entityType),
        _csv(log.entityId),
        _csv(log.payloadJson ?? ''),
      ].join(','),
    );
  }
  return buf.toString();
}

String _csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
