/// Filters ordinary log sources without suppressing explicit incidents.
final class ObservationFilter {
  /// Whether exclusion lists are applied.
  final bool enabled;

  /// Message substrings that exclude matching ordinary logs.
  final List<String> excludedLogs;

  /// URL patterns that exclude matching HTTP logs.
  final List<RegExp> excludedHttpUrls;

  /// Exact runtime type names that exclude matching BLoC logs.
  final List<String> excludedBlocTypes;

  /// Creates an enabled or disabled filter from explicit exclusion lists.
  const ObservationFilter({
    required this.enabled,
    required this.excludedLogs,
    required this.excludedHttpUrls,
    required this.excludedBlocTypes,
  });

  /// Creates a filter that accepts every ordinary log source.
  const ObservationFilter.disabled()
    : enabled = false,
      excludedLogs = const [],
      excludedHttpUrls = const [],
      excludedBlocTypes = const [];

  /// Returns whether an ordinary log with [message] is accepted.
  bool allowsLog(String message) {
    if (!enabled) {
      return true;
    }
    return !excludedLogs.any(message.contains);
  }

  /// Returns whether an HTTP log for [uri] is accepted.
  bool allowsHttpUrl(Uri uri) {
    if (!enabled) {
      return true;
    }
    final value = uri.toString().trim();
    return !excludedHttpUrls.any((filter) => filter.hasMatch(value));
  }

  /// Returns whether the exact [blocType] name is accepted.
  bool allowsBlocType(String blocType) {
    if (!enabled) {
      return true;
    }
    return !excludedBlocTypes.contains(blocType);
  }
}
