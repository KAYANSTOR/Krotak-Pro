/// Next local fire time for the POS daily summary alarm.
///
/// The commercial rule is "after local midnight", not an exact carrier-grade
/// clock. Five minutes past midnight avoids the day-boundary race while the
/// existing idempotency lock still prevents a second send the same day.
DateTime nextDailySummaryFire(DateTime now) {
  final local = now.toLocal();
  var fire = DateTime(local.year, local.month, local.day, 0, 5);
  if (!fire.isAfter(local)) {
    final tomorrow = local.add(const Duration(days: 1));
    fire = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 5);
  }
  return fire;
}
