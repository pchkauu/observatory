import 'package:observatory/src/feature/_common/domain/observation.dart';

abstract interface class ObservationLog {
  void record(Observation observation);
}
