import 'dart:async';

import 'package:launch_mode/launch_mode.dart';

final class IsolateContext {
  static const Symbol contextKey = #observatoryContext;
  static const Symbol zoneNameKey = #observatoryZoneName;

  final LaunchModeType launchMode;
  final String zoneName;

  String get prefix => '${launchMode.name}($zoneName)';

  String format(String message) => message.split('\n').map((line) => '$prefix: $line').join('\n');

  const IsolateContext({
    required this.launchMode,
    required this.zoneName,
  });

  const IsolateContext.unspecified() : launchMode = LaunchModeType.unspecified, zoneName = 'unspecified';

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
