abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

final class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
