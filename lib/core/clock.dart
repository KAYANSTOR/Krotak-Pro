/// Abstraction over system time for testability.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

class FixedClock implements Clock {
  FixedClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime value) => _now = value;
}
