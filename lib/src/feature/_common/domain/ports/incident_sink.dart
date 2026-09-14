import 'package:observatory/src/feature/_common/domain/observation.dart';

abstract interface class IncidentSink {
  Future<void> capture(Observation observation);

  Future<void> bindUser({
    String? id,
    String? email,
  });

  Future<void> clearUser();

  Future<void> bindDevice({
    String? connectedDeviceId,
    String? platformDeviceId,
  });

  Future<void> clearDevice();
}
