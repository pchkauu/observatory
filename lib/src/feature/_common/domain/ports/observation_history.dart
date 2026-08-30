import 'package:observatory/src/feature/_common/domain/observation.dart';

abstract interface class ObservationHistory {
  List<Observation> last({required int limit});
}
