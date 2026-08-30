import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class CaptureIncident {
  final ObservationLog _log;
  final IncidentSink _sink;

  const CaptureIncident({
    required ObservationLog log,
    required IncidentSink sink,
  }) : _log = log,
       _sink = sink;

  Future<void> call(Observation observation) async {
    _log.record(observation);
    await _sink.capture(observation);
  }
}
