import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class RecordObservation {
  final ObservationLog _log;
  final ObservationFilter _filter;

  const RecordObservation({
    required ObservationLog log,
    required ObservationFilter filter,
  }) : _log = log,
       _filter = filter;

  void call(Observation observation) {
    if (!_filter.allowsLog(observation.message)) {
      return;
    }
    _log.record(observation);
  }
}
