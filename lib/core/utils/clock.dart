/// Wraps "now" so tests can control time.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FixedClock extends Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current.toLocal();

  @override
  DateTime nowUtc() => current.toUtc();
}
