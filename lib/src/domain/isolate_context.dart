import 'dart:async';

import 'package:observatory/src/domain/observatory_thread.dart';

final class IsolateContext {
  static const Symbol contextKey = #observatoryContext;
  static const Symbol threadKey = #observatoryThread;
  static const Symbol zoneNameKey = #observatoryZoneName;

  final ObservatoryThread thread;
  final String zoneName;

  String get prefix => '${thread.name}($zoneName)';

  String format(String message) => message.split('\n').map((line) => '$prefix: $line').join('\n');

  const IsolateContext({
    required this.thread,
    required this.zoneName,
  });

  const IsolateContext.unspecified() : thread = ObservatoryThread.unspecified, zoneName = 'unspecified';

  factory IsolateContext.fromZone([Zone? zone, IsolateContext fallback = const IsolateContext.unspecified()]) {
    final current = zone ?? Zone.current;
    final provider = current[contextKey];
    final base = provider is IsolateContext Function() ? provider() : fallback;
    final thread = current[threadKey];
    final zoneName = current[zoneNameKey];
    return IsolateContext(
      thread: thread is ObservatoryThread ? thread : base.thread,
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
