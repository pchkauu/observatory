import 'package:observatory/src/feature/_common/domain/isolate_context.dart';
import 'package:observatory/src/feature/_common/domain/log_level.dart';

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

  String get prefixedMessage => '${isolate.prefix}: $message';
}
