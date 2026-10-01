import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/local_maintenance_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 12);

  group('isRetentionDue', () {
    test('is due when no previous stamp exists', () {
      expect(isRetentionDue(now: now, lastRunIso: null), isTrue);
      expect(isRetentionDue(now: now, lastRunIso: '  '), isTrue);
    });

    test('is due when the stamp cannot be parsed', () {
      expect(isRetentionDue(now: now, lastRunIso: 'not-a-date'), isTrue);
    });

    test('skips a pass that already ran within 20 hours', () {
      final recent = now.subtract(const Duration(hours: 6)).toIso8601String();
      expect(isRetentionDue(now: now, lastRunIso: recent), isFalse);
    });

    test('is due after 20 hours so a daily cycle is not skipped', () {
      final old = now.subtract(const Duration(hours: 20)).toIso8601String();
      expect(isRetentionDue(now: now, lastRunIso: old), isTrue);
    });
  });
}
