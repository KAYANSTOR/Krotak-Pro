/// تصدير سجل التدقيق إلى CSV دون الاعتماد على الواجهة أو قاعدة البيانات.
library;

import '../entities/audit.dart';

/// يهرّب خلية CSV ويمنع حقن الصيغ في Excel.
String auditCsvCell(String value) {
  var cell = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
  if (cell.startsWith('=') ||
      cell.startsWith('+') ||
      cell.startsWith('-') ||
      cell.startsWith('@')) {
    cell = "'$cell";
  }
  final needsQuote = cell.contains(',') || cell.contains('"') || cell.contains('\n');
  if (needsQuote || cell.startsWith("'")) {
    return '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}

/// CSV بترويسة ثابتة. القيود تُكتب كما وصلت (الأحدث أولاً إن رُتبت كذلك).
String buildAuditLogCsv(List<AuditLog> logs) {
  final buf = StringBuffer(
    'id,occurredAt,action,entityType,entityId,payloadJson\n',
  );
  for (final log in logs) {
    buf.writeln([
      auditCsvCell(log.id),
      auditCsvCell(log.occurredAt.toIso8601String()),
      auditCsvCell(log.action),
      auditCsvCell(log.entityType),
      auditCsvCell(log.entityId),
      auditCsvCell(log.payloadJson ?? ''),
    ].join(','));
  }
  return buf.toString();
}
