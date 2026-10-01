import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/services/audit_log_export.dart';

void main() {
  test('audit csv escapes commas and formula injection', () {
    final csv = buildAuditLogCsv([
      AuditLog(
        id: 'a1',
        entityType: 'customer',
        entityId: 'c,1',
        action: '=cmd',
        occurredAt: DateTime.utc(2026, 10, 1, 8),
        payloadJson: 'say "hi"',
      ),
    ]);
    expect(
      csv.split('\n').first,
      'id,occurredAt,action,entityType,entityId,payloadJson',
    );
    expect(csv.contains("'=cmd"), isTrue);
    expect(csv.contains('"c,1"'), isTrue);
    expect(csv.contains('"say ""hi"""'), isTrue);
  });

  test('empty audit export is header only', () {
    expect(
      buildAuditLogCsv(const []),
      'id,occurredAt,action,entityType,entityId,payloadJson\n',
    );
  });
}
