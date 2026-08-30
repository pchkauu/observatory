import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:talker/talker.dart' as talker;

final class TalkerLogFilter implements talker.LoggerFilter {
  final ObservationFilter filter;

  const TalkerLogFilter({
    required this.filter,
  });

  @override
  // ignore: avoid_annotating_with_dynamic
  bool shouldLog(dynamic msg, talker.LogLevel level) {
    if (msg is! String) {
      return true;
    }
    return filter.allowsLog(msg);
  }
}
