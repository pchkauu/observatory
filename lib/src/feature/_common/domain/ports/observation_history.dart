import 'package:observatory/src/feature/_common/domain/log_level.dart';
import 'package:observatory/src/feature/_common/domain/observation.dart';

/// Provides bounded access to prepared observations.
abstract interface class ObservationHistory {
  /// Returns at most [limit] newest observations at or above [minimumLevel].
  List<Observation> last({required int limit, LogLevel minimumLevel = LogLevel.verbose});
}
