import 'package:observatory/src/feature/_common/data/talker/error_classifier.dart';
import 'package:observatory/src/feature/_common/data/talker/talker_log_filter.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:talker/talker.dart' as talker;
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

final class TalkerObservationLog implements ObservationLog, ObservationHistory {
  final Talker talker;
  final FrameworkErrorClassifier classifier;
  final TalkerLogFilter talkerFilter;
  final List<Observation> _history = [];

  TalkerObservationLog({
    required this.talker,
    ObservationFilter filter = const ObservationFilter.disabled(),
    this.classifier = const FrameworkErrorClassifier(),
  }) : talkerFilter = TalkerLogFilter(filter: filter);

  @override
  void record(Observation observation) {
    _history.add(observation);
    final message = ErrorIdentity.formatLogMessage(
      observation.prefixedMessage,
      error: observation.error,
      describedType: classifier.describe(observation.error),
      typeIdentifier: classifier.typeIdentifier(observation.error),
    );
    if (!talkerFilter.shouldLog(message, toTalkerLogLevel(observation.level))) {
      return;
    }
    switch (observation.level) {
      case LogLevel.verbose:
        talker.verbose(message, observation.error, observation.stackTrace);
      case LogLevel.debug:
        talker.debug(message, observation.error, observation.stackTrace);
      case LogLevel.info:
        talker.info(message, observation.error, observation.stackTrace);
      case LogLevel.warning:
        talker.warning(message, observation.error, observation.stackTrace);
      case LogLevel.error:
        talker.error(message, observation.error, observation.stackTrace);
      case LogLevel.critical:
        talker.critical(message, observation.error, observation.stackTrace);
    }
  }

  @override
  List<Observation> last({required int limit}) {
    if (_history.length <= limit) {
      return List<Observation>.of(_history);
    }
    return _history.sublist(_history.length - limit);
  }
}

talker.LogLevel toTalkerLogLevel(LogLevel level) {
  return switch (level) {
    LogLevel.verbose => talker.LogLevel.verbose,
    LogLevel.debug => talker.LogLevel.debug,
    LogLevel.info => talker.LogLevel.info,
    LogLevel.warning => talker.LogLevel.warning,
    LogLevel.error => talker.LogLevel.error,
    LogLevel.critical => talker.LogLevel.critical,
  };
}
