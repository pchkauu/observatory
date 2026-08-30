import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class SilentObservationLog implements ObservationLog, ObservationHistory {
  const SilentObservationLog();

  @override
  void record(Observation observation) {}

  @override
  List<Observation> last({required int limit}) => const [];
}

final class SilentIncidentSink implements IncidentSink {
  const SilentIncidentSink();

  @override
  Future<void> capture(Observation observation) async {}

  @override
  Future<void> bindUser({
    String? id,
    String? email,
  }) async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> bindDevice({
    String? connectedDeviceId,
    String? platformDeviceId,
  }) async {}

  @override
  Future<void> clearDevice() async {}
}
