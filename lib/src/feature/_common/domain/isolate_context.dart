import 'dart:async';

import 'package:observatory/src/feature/_common/domain/observatory_thread.dart';

final class IsolateContext {
  static const Symbol threadKey = #observatoryThread;
  static const Symbol zoneNameKey = #observatoryZoneName;

  final ObservatoryThread thread;
  final String zoneName;

  String get prefix => '${thread.name}($zoneName)';

  const IsolateContext({
    required this.thread,
    required this.zoneName,
  });

  const IsolateContext.unspecified() : thread = ObservatoryThread.unspecified, zoneName = 'unspecified';

  factory IsolateContext.fromZone([Zone? zone]) {
    final current = zone ?? Zone.current;
    final thread = current[threadKey];
    final zoneName = current[zoneNameKey];
    return IsolateContext(
      thread: thread is ObservatoryThread ? thread : ObservatoryThread.unspecified,
      zoneName: zoneName is String && zoneName.isNotEmpty ? zoneName : 'unspecified',
    );
  }

  static String normalizeZoneName(String zoneName) {
    final normalizedZoneName = zoneName.trim();
    if (normalizedZoneName.isEmpty) {
      return 'unspecified';
    }
    if (normalizedZoneName.length > 20) {
      return normalizedZoneName.substring(0, 20);
    }
    return normalizedZoneName;
  }
}
