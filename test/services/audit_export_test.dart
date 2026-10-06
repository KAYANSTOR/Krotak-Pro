import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/services/audit_export.dart';

void main() {
  test('buildAuditCsv escapes quotes and includes BOM', () {
    final csv = buildAuditCsv([
      AuditLog(
        id: 'a1',
        entityType: 'sale',
        entityId: 's1',
        action: 'manual_completed',
        occurredAt: DateTime.utc(2026, 9, 29, 10),
        payloadJson: '{"note":"قال \\"تم\\""}',
      ),
    ]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('id,occurred_at,action,entity_type,entity_id,payload'));
    expect(csv, contains('manual_completed'));
    expect(csv, contains('""تم""'));
  });

  test('empty audit list still has header', () {
    final csv = buildAuditCsv(const []);
    expect(csv.split('\n').first.contains('id'), isTrue);
    expect(csv.trim().split('\n').length, 1);
  });
}
