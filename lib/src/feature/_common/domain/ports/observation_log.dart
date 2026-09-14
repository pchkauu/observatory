import 'package:observatory/src/feature/_common/domain/observation.dart';

/// Stores prepared observations in the shared local log stream.
abstract interface class ObservationLog {
  /// Records [observation] as an explicit incident.
  void record(Observation observation);
}
