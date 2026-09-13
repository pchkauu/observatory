import 'package:observatory/src/domain/log_level.dart';
import 'package:observatory/src/domain/observation.dart';

abstract interface class ObservationHistory {
  List<Observation> last({required int limit, LogLevel minimumLevel = LogLevel.verbose});
}
