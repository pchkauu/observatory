import 'package:domain_error/domain_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/application/silent_ports.dart';
import 'package:observatory/src/feature/_common/data/sentry/sentry_incident_sink.dart';
import 'package:observatory/src/feature/_common/data/talker/talker_observation_log.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker/talker.dart' hide LogLevel;

void main() {
  group('SentryIncidentSink options', () {
    test('applies release, dist, low screenshots and full request bodies for foreground init', () {
      final sink = _sink();
      final options = SentryFlutterOptions();

      sink.applyFlutterOptions(options);

      expect(options.environment, 'production');
      expect(options.release, 'mobile@1.0.0+42');
      expect(options.dist, '42');
      expect(options.attachScreenshot, isTrue);
      expect(options.screenshotQuality, SentryScreenshotQuality.low);
      expect(options.maxRequestBodySize, MaxRequestBodySize.always);
    });

    test('applies release, dist and full request bodies for background init', () {
      final sink = _sink();
      final options = SentryOptions();

      sink.applyBackgroundOptions(options);

      expect(options.environment, 'production');
      expect(options.release, 'mobile@1.0.0+42');
      expect(options.dist, '42');
      expect(options.maxRequestBodySize, MaxRequestBodySize.always);
    });
  });

  group('SentryIncidentSink beforeSend', () {
    test('drops repeated events inside dedupe ttl', () async {
      final clock = _MutableClock(DateTime.utc(2026));
      final sink = _sink(clock: clock);

      final first = await sink.beforeSend(_event(), Hint());
      final second = await sink.beforeSend(_event(), Hint());

      expect(first, isNotNull);
      expect(second, isNull);
    });

    test('allows repeated events after dedupe ttl expires', () async {
      final clock = _MutableClock(DateTime.utc(2026));
      final sink = _sink(clock: clock);

      final first = await sink.beforeSend(_event(), Hint());
      clock.value = clock.value.add(const Duration(minutes: 2));
      final second = await sink.beforeSend(_event(), Hint());

      expect(first, isNotNull);
      expect(second, isNotNull);
    });

    test('adds stable failure type identifier to Sentry event tags and contexts', () async {
      final sink = _sink();
      const failure = _SignatureFailure(message: 'signature mismatch');
      final event = SentryEvent(
        throwable: failure,
        exceptions: [
          SentryException(
            type: 'a',
            value: 'b',
            throwable: failure,
          ),
        ],
      );

      final processed = await sink.beforeSend(event, Hint());

      expect(processed, isNotNull);
      expect(processed!.tags?['failure.type_identifier'], 'SignatureFailure');
      expect(processed.contexts['failure'], {
        'type_identifier': 'SignatureFailure',
      });
    });

    test('adds stable failure type identifier to observation breadcrumbs', () async {
      final talker = Talker(
        settings: TalkerSettings(
          useConsoleLogs: false,
        ),
      );
      final history = TalkerObservationLog(talker: talker);
      const failure = _SignatureFailure(message: 'signature mismatch');
      history.record(
        Observation(
          message: 'Sync failed',
          level: LogLevel.warning,
          error: failure,
          isolate: const IsolateContext.unspecified(),
          time: DateTime.utc(2026),
        ),
      );

      final sink = _sink(
        history: history,
        spec: _sentrySpec(attachLogs: true),
      );

      final processed = await sink.beforeSend(_event(), Hint());

      expect(
        processed?.breadcrumbs?.map((breadcrumb) => breadcrumb.message).join('\n'),
        contains('failure.type_identifier=SignatureFailure'),
      );
    });
  });
}

SentryIncidentSink _sink({
  ObservationClock? clock,
  ObservationHistory? history,
  SentrySpec? spec,
}) {
  final resolvedClock = clock ?? const SystemObservationClock();
  final resolvedSpec = spec ?? _sentrySpec();
  return SentryIncidentSink(
    spec: resolvedSpec,
    history: history ?? const SilentObservationLog(),
    dedupe: DedupePolicy(
      ttl: resolvedSpec.dedupeTtl,
      maxEntries: resolvedSpec.dedupeMaxEntries,
      clock: resolvedClock,
    ),
    preferFileLine: false,
  );
}

SentrySpec _sentrySpec({
  bool attachLogs = false,
}) {
  return SentrySpec(
    enabled: true,
    appPackageName: 'mobile',
    dsn: 'https://public@example.com/1',
    environment: attachLogs ? 'test' : 'production',
    release: attachLogs ? 'mobile@test' : 'mobile@1.0.0+42',
    dist: attachLogs ? '1' : '42',
    sampleRate: 1,
    attachScreenshot: !attachLogs,
    attachLogs: attachLogs,
    logsMaxBreadcrumbs: attachLogs ? 10 : 100,
    logsLevel: attachLogs ? LogLevel.verbose : LogLevel.warning,
    maxBreadcrumbs: attachLogs ? 10 : 100,
    dedupeTtl: const Duration(minutes: 1),
    dedupeMaxEntries: attachLogs ? 10 : 1000,
    anrEnabled: true,
    anrTimeoutInterval: const Duration(seconds: 5),
    enableAppHangTracking: true,
    appHangTimeoutInterval: const Duration(seconds: 2),
  );
}

SentryEvent _event() {
  return SentryEvent(
    exceptions: [
      SentryException(
        type: 'StateError',
        value: 'Bad state',
      ),
    ],
    transaction: 'AlertListBloc',
  );
}

final class _MutableClock implements ObservationClock {
  DateTime value;

  _MutableClock(this.value);

  @override
  DateTime now() => value;
}

final class _SignatureFailure extends DomainError {
  @override
  String get typeIdentifier => 'SignatureFailure';

  const _SignatureFailure({
    super.message,
  });
}
