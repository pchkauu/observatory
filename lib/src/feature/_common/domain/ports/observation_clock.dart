/// Supplies timestamps for observations and time-based policies.
abstract interface class ObservationClock {
  /// Returns the current timestamp.
  DateTime now();
}

/// Uses the system clock and returns UTC timestamps.
final class SystemObservationClock implements ObservationClock {
  /// Creates a system-backed observation clock.
  const SystemObservationClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
