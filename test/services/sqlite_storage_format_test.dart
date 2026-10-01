import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/local_maintenance_service.dart';

void main() {
  group('formatStorageBytes', () {
    test('formats bytes, kibibytes and mebibytes in Arabic units', () {
      expect(formatStorageBytes(0), '0 بايت');
      expect(formatStorageBytes(512), '512 بايت');
      expect(formatStorageBytes(2048), '2.0 ك.ب');
      expect(formatStorageBytes(5 * 1024 * 1024), '5.0 م.ب');
    });

    test('clamps negative values', () {
      expect(formatStorageBytes(-10), '0 بايت');
    });
  });

  group('SqliteStorageSnapshot warning', () {
    test('flags usage at or above the 80 MiB threshold', () {
      const threshold = LocalMaintenanceService.defaultWarningThresholdBytes;
      const below = SqliteStorageSnapshot(
        pageCount: 1,
        pageSize: 4096,
        usedBytes: threshold - 1,
        reclaimableBytes: 0,
        warning: false,
      );
      const at = SqliteStorageSnapshot(
        pageCount: 1,
        pageSize: 4096,
        usedBytes: threshold,
        reclaimableBytes: 0,
        warning: true,
      );
      expect(below.warning, isFalse);
      expect(at.usedBytes >= threshold, isTrue);
      expect(at.warning, isTrue);
    });
  });
}
