final class ObservationFilter {
  final bool enabled;
  final List<String> excludedLogs;
  final List<RegExp> excludedHttpUrls;
  final List<String> excludedBlocTypes;

  const ObservationFilter({
    required this.enabled,
    required this.excludedLogs,
    required this.excludedHttpUrls,
    required this.excludedBlocTypes,
  });

  const ObservationFilter.disabled()
    : enabled = false,
      excludedLogs = const [],
      excludedHttpUrls = const [],
      excludedBlocTypes = const [];

  bool allowsLog(String message) {
    if (!enabled) {
      return true;
    }
    return !excludedLogs.any(message.contains);
  }

  bool allowsHttpUrl(Uri uri) {
    if (!enabled) {
      return true;
    }
    final value = uri.toString().trim();
    return !excludedHttpUrls.any((filter) => filter.hasMatch(value));
  }

  bool allowsBlocType(String blocType) {
    if (!enabled) {
      return true;
    }
    return !excludedBlocTypes.contains(blocType);
  }
}
