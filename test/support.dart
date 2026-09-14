import 'dart:convert';
import 'dart:ui';

import 'package:observatory/observatory.dart';
import 'package:observatory/src/data/log_sanitizer.dart';
import 'package:observatory/src/data/sentry/sentry_incident_sink.dart';
import 'package:observatory/src/data/talker/managed_talker.dart';
import 'package:observatory/src/domain/ports/observation_history.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// Exercise the SDK Flutter hook directly without native initialization.
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/flutter_error_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/utils/platform_dispatcher_wrapper.dart';

final class MutableClock implements ObservationClock {
  DateTime value = DateTime.utc(2026, 9, 13);
  @override
  DateTime now() => value;
}

ManagedTalker createLog({
  int limit = 1000,
  ObservationFilter filter = const ObservationFilter.disabled(),
  void Function(String)? output,
  void Function(String)? reportFailure,
}) => ManagedTalker(
  clock: MutableClock(),
  context: () => const IsolateContext(launchMode: LaunchModeType.foreground, zoneName: 'main'),
  sanitizer: const LogSanitizer(RedactionPolicy()),
  observationFilter: filter,
  historyLimit: limit,
  output: output ?? (_) {},
  reportFailure: reportFailure ?? (_) {},
);

SentrySpec sentrySpec({
  bool attachLogs = true,
  int logsLimit = 10,
  int maxBreadcrumbs = 10,
  LogLevel logsLevel = LogLevel.warning,
  String dsn = 'https://public@example.com/1',
}) => SentrySpec(
  enabled: true,
  appPackageName: 'mobile',
  dsn: dsn,
  environment: 'test',
  release: 'mobile@3.0.0',
  dist: '1',
  sampleRate: 1,
  attachScreenshot: true,
  attachLogs: attachLogs,
  logsMaxBreadcrumbs: logsLimit,
  logsLevel: logsLevel,
  maxBreadcrumbs: maxBreadcrumbs,
  dedupeTtl: const Duration(minutes: 1),
  dedupeMaxEntries: 100,
  anrEnabled: false,
  anrTimeoutInterval: const Duration(seconds: 5),
  enableAppHangTracking: false,
  appHangTimeoutInterval: const Duration(seconds: 2),
);

SentryIncidentSink createSink({
  SentrySpec? spec,
  ObservationHistory? history,
  MutableClock? clock,
  void Function(String)? reportFailure,
}) {
  final settings = spec ?? sentrySpec();
  return SentryIncidentSink(
    spec: settings,
    history: history ?? createLog(),
    dedupe: DedupePolicy(
      ttl: settings.dedupeTtl,
      maxEntries: settings.dedupeMaxEntries,
      clock: clock ?? MutableClock(),
    ),
    sanitizer: const LogSanitizer(RedactionPolicy()),
    context: () => const IsolateContext(launchMode: LaunchModeType.foreground, zoneName: 'main'),
    reportFailure: reportFailure ?? (_) {},
    preferFileLine: true,
  );
}

final class RecordingTransport implements Transport {
  final List<Map<String, dynamic>> events = [];
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      if (item.header.type == 'event' || item.header.type == 'transaction') {
        events.add(jsonDecode(utf8.decode(await item.dataFactory())) as Map<String, dynamic>);
      }
    }
    return envelope.header.eventId;
  }
}

Future<void> initializeTestSentry(SentryIncidentSink sink, RecordingTransport transport, {bool flutterHooks = false}) =>
    Sentry.init(
      (options) {
        sink.applyBackgroundOptions(options);
        options.integrations.toList().forEach(options.removeIntegration);
        if (flutterHooks) {
          options
            ..addIntegration(FlutterErrorIntegration())
            // TestPlatformDispatcher drops onError assignments; use the real dispatcher.
            // ignore: invalid_use_of_internal_member
            ..addIntegration(
              OnErrorIntegration(dispatchWrapper: PlatformDispatcherWrapper(PlatformDispatcher.instance)),
            );
        }
        options
          ..transport = transport
          ..debug = false
          // Surface SDK failures in tests instead of silently dropping assertions.
          // ignore: invalid_use_of_internal_member
          ..automatedTestMode = true
          ..sendClientReports = false;
      },
      // Use Flutter options for the real Flutter/platform integrations in local tests.
      // ignore: invalid_use_of_internal_member
      options: flutterHooks ? SentryFlutterOptions() : SentryOptions(),
    );
