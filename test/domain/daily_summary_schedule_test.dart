import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/daily_summary_schedule.dart';

void main() {
  test('before midnight schedules the same local day at 00:05', () {
    final now = DateTime(2026, 10, 1, 21, 30);
    expect(nextDailySummaryFire(now), DateTime(2026, 10, 2, 0, 5));
  });

  test('after 00:05 schedules the next local day', () {
    final now = DateTime(2026, 10, 2, 0, 6);
    expect(nextDailySummaryFire(now), DateTime(2026, 10, 3, 0, 5));
  });

  test('exactly 00:05 moves to the following day', () {
    final now = DateTime(2026, 10, 2, 0, 5);
    expect(nextDailySummaryFire(now), DateTime(2026, 10, 3, 0, 5));
  });
}
