import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class BindDevice {
  final IncidentSink _sink;

  const BindDevice({
    required IncidentSink sink,
  }) : _sink = sink;

  Future<void> call({
    String? connectedDeviceId,
    String? platformDeviceId,
  }) {
    return _sink.bindDevice(
      connectedDeviceId: connectedDeviceId,
      platformDeviceId: platformDeviceId,
    );
  }

  Future<void> clear() {
    return _sink.clearDevice();
  }
}
