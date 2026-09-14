import 'package:observatory/src/feature/_common/domain/isolate_context.dart';
import 'package:observatory/src/feature/_common/domain/log_level.dart';

/// Immutable event prepared for local logging or incident capture.
final class Observation {
  /// Operation message before context prefixing.
  final String message;

  /// Event severity.
  final LogLevel level;

  /// Original failure object when the event describes an exception.
  final Object? error;

  /// Original stack trace associated with [error].
  final StackTrace? stackTrace;

  /// Launch-mode and zone context captured at event receipt.
  final IsolateContext isolate;

  /// Event receipt time.
  final DateTime time;

  /// Creates an immutable observation.
  const Observation({
    required this.message,
    required this.level,
    required this.isolate,
    required this.time,
    this.error,
    this.stackTrace,
  });

  /// Message with context added to every line.
  String get prefixedMessage => isolate.format(message);
}
