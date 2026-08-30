abstract interface class ObservationClock {
  DateTime now();
}

final class SystemObservationClock implements ObservationClock {
  const SystemObservationClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
