import 'package:observatory/src/domain/isolate_context.dart';
import 'package:observatory/src/domain/log_level.dart';

final class Observation {
  final String message;
  final LogLevel level;
  final Object? error;
  final StackTrace? stackTrace;
  final IsolateContext isolate;
  final DateTime time;

  const Observation({
    required this.message,
    required this.level,
    required this.isolate,
    required this.time,
    this.error,
    this.stackTrace,
  });

  String get prefixedMessage => isolate.format(message);
}
