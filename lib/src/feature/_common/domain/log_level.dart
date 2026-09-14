/// Severity assigned to a local record or captured incident.
enum LogLevel {
  /// Fine-grained tracing information.
  verbose,

  /// Diagnostic information useful during development.
  debug,

  /// Normal operational information.
  info,

  /// A recoverable or potentially harmful condition.
  warning,

  /// A failed operation that requires attention.
  error,

  /// A severe failure that can stop normal operation.
  critical,
}
