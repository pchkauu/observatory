import 'package:observatory/src/domain/observation.dart';

abstract interface class ObservationLog {
  void record(Observation observation);
}
