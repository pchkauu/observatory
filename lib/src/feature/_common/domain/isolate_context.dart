import 'dart:async';

import 'package:launch_mode/launch_mode.dart';

/// Launch-mode and zone metadata captured when an event enters Observatory.
final class IsolateContext {
  /// Zone key that provides the active runtime context.
  static const Symbol contextKey = #observatoryContext;

  /// Zone key that overrides the operation name for nested work.
  static const Symbol zoneNameKey = #observatoryZoneName;

  /// Detected launch mode for the event origin.
  final LaunchModeType launchMode;

  /// Normalized operation-zone name.
  final String zoneName;

  /// Prefix rendered as `launchMode(zoneName)`.
  String get prefix => '${launchMode.name}($zoneName)';

  /// Prefixes every line of [message] with this context.
  String format(String message) => message.split('\n').map((line) => '$prefix: $line').join('\n');

  /// Creates an event context from an explicit launch mode and zone name.
  const IsolateContext({required this.launchMode, required this.zoneName});

  /// Creates a fallback context with unspecified launch mode and zone name.
  const IsolateContext.unspecified() : launchMode = LaunchModeType.unspecified, zoneName = 'unspecified';

  /// Resolves context from [zone], falling back to [fallback].
  ///
  /// A scoped background launch mode overrides the runtime launch mode.
  factory IsolateContext.fromZone([Zone? zone, IsolateContext fallback = const IsolateContext.unspecified()]) {
    final current = zone ?? Zone.current;
    final provider = current[contextKey];
    final base = provider is IsolateContext Function() ? provider() : fallback;
    final detectedMode = current.run(() => LaunchMode.current);
    final zoneName = current[zoneNameKey];
    return IsolateContext(
      launchMode: detectedMode == LaunchModeType.unspecified ? base.launchMode : detectedMode,
      zoneName: zoneName is String && zoneName.isNotEmpty ? normalizeZoneName(zoneName) : base.zoneName,
    );
  }

  /// Trims [zoneName], replaces line breaks, and limits it to 20 characters.
  static String normalizeZoneName(String zoneName) {
    final normalizedZoneName = zoneName.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (normalizedZoneName.isEmpty) {
      return 'unspecified';
    }
    if (normalizedZoneName.length > 20) {
      return normalizedZoneName.substring(0, 20);
    }
    return normalizedZoneName;
  }
}
