import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:domain_error/domain_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/domain/ports/observation_history.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../support.dart';

void main() {
  tearDown(Sentry.close);

  test('foreground/background options preserve privacy and disable competing deduplication', () {
    final sink = createSink();
    final flutter = SentryFlutterOptions();
    final dart = SentryOptions();
    sink
      ..applyFlutterOptions(flutter)
      ..applyBackgroundOptions(dart);
    expect(flutter.release, 'mobile@3.0.0');
    expect(flutter.dist, '1');
    expect(flutter.attachScreenshot, isTrue);
    expect(flutter.privacy.maskAllText, isTrue);
    expect(flutter.privacy.maskAllImages, isTrue);
    expect(flutter.maxRequestBodySize, isNot(MaxRequestBodySize.always));
    expect(flutter.enableDeduplication, isFalse);
    expect(dart.enableDeduplication, isFalse);
    expect(dart.beforeSendTransaction, isNotNull);
    expect(dart.beforeBreadcrumb, isNotNull);
  });

  test('dedupe respects operation, nearest location, context and TTL', () async {
    final clock = MutableClock();
    final sink = createSink(clock: clock);
    expect(await sink.beforeSend(event(), Hint()), isNotNull);
    expect(await sink.beforeSend(event(), Hint()), isNull);
    expect(await sink.beforeSend(event(line: 20), Hint()), isNotNull);
    expect(await sink.beforeSend(event(message: 'another operation'), Hint()), isNotNull);
    clock.value = clock.value.add(const Duration(minutes: 2));
    expect(await sink.beforeSend(event(), Hint()), isNotNull);
    expect(await sink.beforeSend(SentryEvent(message: SentryMessage('plain'), exceptions: []), Hint()), isNotNull);
    expect(
      await sink.beforeSend(SentryEvent(message: SentryMessage('plain'), tags: {'zoneName': 'other'}), Hint()),
      isNotNull,
    );
  });

  test('preserves exception chain, operation and transaction; annotates nearest frame separately', () async {
    const failure = SignatureFailure(message: 'signature mismatch');
    final source = event(throwable: failure);
    source.exceptions!.add(SentryException(type: 'InnerError', value: 'original inner reason'));
    source.exceptions!.first.throwable = failure;
    final processed = await createSink().beforeSend(source, Hint());
    expect(processed, isNotNull);
    expect(processed!.message!.formatted, 'sync profile');
    expect(processed.transaction, 'ProfileRoute');
    expect(processed.exceptions!.map((entry) => entry.type), ['StateError', 'InnerError']);
    expect(processed.exceptions!.map((entry) => entry.value), ['original reason', 'original inner reason']);
    expect(processed.tags!['failure.type_identifier'], 'SignatureFailure');
    expect((processed.contexts['observatory'] as Map)['location'], 'sync.dart:12');
  });

  test('breadcrumb severity is applied before count; final list respects total maximum', () async {
    final log = createLog()
      ..warning('keep oldest warning')
      ..info('skip info')
      ..error('keep newest error')
      ..debug('skip latest debug');
    final sink = createSink(history: log, spec: sentrySpec(logsLimit: 2, maxBreadcrumbs: 2));
    final source = event()..breadcrumbs = [Breadcrumb(message: 'existing')];
    final processed = await sink.beforeSend(source, Hint());
    expect(processed!.breadcrumbs, hasLength(2));
    expect(processed.breadcrumbs!.first.message, 'foreground(main): keep oldest warning');
    expect(processed.breadcrumbs!.last.message, 'foreground(main): keep newest error');
    expect(processed.breadcrumbs!.last.data!['zoneName'], 'main');
    final zero = await createSink(history: log, spec: sentrySpec(maxBreadcrumbs: 0)).beforeSend(event(), Hint());
    expect(zero!.breadcrumbs, isEmpty);
  });

  test('scrubs request, response hint, contexts, extras, breadcrumbs and original exception values', () async {
    final source = event()
      ..request = SentryRequest.fromUri(
        uri: Uri.parse('https://user:secret@example.com?name=public&token=query-secret&api%4Bey=encoded-secret'),
        headers: {'Authorization': 'header-secret'},
        data: {'password': 'body-secret'},
      )
      ..contexts['custom'] = {'secret': 'context-secret', 'name': 'safe'}
      // ignore: deprecated_member_use
      ..extra = {'apiKey': 'extra-secret'}
      ..breadcrumbs = [
        Breadcrumb(message: 'GET https://example.com?token=crumb-secret', data: {'token': 'data-secret'}),
      ]
      ..exceptions!.first.value = 'password=value-secret';
    final hint = Hint.withResponse(SentryResponse(data: {'token': 'response-secret'}));
    final processed = await createSink(spec: sentrySpec(attachLogs: false)).beforeSend(source, hint);
    expect(processed, isNotNull);
    final payload = jsonEncode([processed!.toJson(), hint.response!.toJson()]);
    for (final secret in [
      'user:secret',
      'query-secret',
      'header-secret',
      'body-secret',
      'context-secret',
      'extra-secret',
      'crumb-secret',
      'data-secret',
      'value-secret',
      'response-secret',
      'encoded-secret',
    ]) {
      expect(payload, isNot(contains(secret)), reason: secret);
    }
    expect(payload, contains('safe'));
  });

  test('real SDK transport receives messages without errors and full incident context', () async {
    final transport = RecordingTransport();
    final sink = createSink(spec: sentrySpec(attachLogs: false));
    await initializeTestSentry(sink, transport);
    final time = DateTime.utc(2026, 9, 13);
    await sink.capture(
      Observation(
        message: 'no exception',
        level: LogLevel.warning,
        time: time,
        isolate: const IsolateContext(launchMode: LaunchModeType.background, zoneName: 'sync'),
      ),
    );
    await sink.capture(
      Observation(
        message: 'failed operation',
        level: LogLevel.error,
        time: time,
        isolate: const IsolateContext(launchMode: LaunchModeType.background, zoneName: 'sync'),
        error: StateError('original cause'),
        stackTrace: StackTrace.fromString('#0 refresh (package:mobile/sync.dart:12:3)'),
      ),
    );
    expect(transport.events, hasLength(2));
    final message = SentryEvent.fromJson(transport.events.first);
    expect(message.message!.formatted, 'no exception');
    expect(message.timestamp, time);
    expect(message.level, SentryLevel.warning);
    expect(message.tags, containsPair('thread', 'background'));
    expect(message.tags, containsPair('zoneName', 'sync'));
    final incident = SentryEvent.fromJson(transport.events.last);
    expect(incident.message!.formatted, 'failed operation');
    expect(incident.exceptions!.first.value, contains('original cause'));
  });

  test('transaction spans and trace data use the same sanitizer', () async {
    final transport = RecordingTransport();
    final sink = createSink();
    await initializeTestSentry(sink, transport);
    final transaction = Sentry.startTransaction('sync', 'operation', bindToScope: true)
      ..setData('password', 'trace-secret');
    final span = transaction.startChild('http.client', description: 'GET https://example.com?token=span-secret')
      ..setData('Authorization', 'span-data-secret')
      ..setTag('apiKey', 'span-tag-secret');
    await span.finish();
    await transaction.finish();
    final payload = jsonEncode(transport.events);
    expect(transport.events, hasLength(1));
    for (final secret in ['trace-secret', 'span-secret', 'span-data-secret', 'span-tag-secret']) {
      expect(payload, isNot(contains(secret)));
    }
  });

  test('history failure does not suppress an incident', () async {
    final failures = <String>[];
    final processed = await createSink(
      history: ThrowingHistory(),
      reportFailure: failures.add,
    ).beforeSend(event(), Hint());
    expect(processed, isNotNull);
    expect(failures, ['Log history is unavailable for Sentry']);
  });

  test('JSON messages and long stacks remain valid after bounded sanitization', () async {
    final source = SentryEvent(
      message: SentryMessage('{"tokens":["secret-one","secret-two"],"value":42}'),
      exceptions: [
        SentryException(
          type: 'Failure',
          value: '{"password":"secret-value"}',
          stackTrace: SentryStackTrace(
            frames: List.generate(
              600,
              (index) => SentryStackFrame(
                function: 'frame$index',
                fileName: 'sync.dart',
                lineNo: index,
                vars: {'token': 'secret-local'},
                preContext: ['password=secret-source'],
                framesOmitted: [1, 2],
              ),
            ),
            registers: {'r0': 'safe'},
          ),
        ),
      ],
    );
    final result = await createSink().beforeSend(source, Hint());
    expect(result, isNotNull);
    final json = jsonEncode(result!.toJson());
    for (final secret in ['secret-one', 'secret-two', 'secret-value', 'secret-local', 'secret-source']) {
      expect(json, isNot(contains(secret)));
    }
    expect(result.message!.formatted, contains('42'));
    expect(result.exceptions!.single.stackTrace!.frames.last.function, 'frame599');
    expect(json, contains('<truncated>'));
  });

  test('malformed optional data does not drop the operation or leak raw values', () async {
    final source = event()..request = SentryRequest(queryString: 'token=%FF');
    final result = await createSink().beforeSend(source, Hint());
    expect(result, isNotNull);
    expect(result!.message!.formatted, 'sync profile');
    expect(result.exceptions!.first.type, 'StateError');
    expect(result.tags!['observatory.preparation'], 'failed');
    expect(jsonEncode(result.toJson()), isNot(contains('%FF')));
  });

  test('SDK breadcrumbs retain receipt context and complete multiline prefixes', () {
    final sink = createSink();
    final options = SentryOptions();
    sink.applyBackgroundOptions(options);
    final breadcrumb = options.beforeBreadcrumb!(Breadcrumb(message: 'line\n' * 2000), Hint());
    expect(breadcrumb, isNotNull);
    expect(breadcrumb!.data, containsPair('zoneName', 'main'));
    expect(breadcrumb.message!.length, lessThanOrEqualTo(16384));
    expect(breadcrumb.message!.split('\n').every((line) => line.startsWith('foreground(main): ')), isTrue);
    expect(options.recordHttpBreadcrumbs, isFalse);
    expect(
      options.beforeBreadcrumb!(
        RouteObserverBreadcrumb(navigationType: 'push'),
        Hint(),
      ),
      isNull,
    );
  });

  test('SDK transport preserves Dio cause chain and original HTTP data', () async {
    final transport = RecordingTransport();
    final sink = createSink();
    await initializeTestSentry(sink, transport);
    final dio = Dio()..addSentry(captureFailedRequests: false);
    final request = RequestOptions(
      path: 'https://example.com?token=query-secret',
      data: {'password': 'body-secret'},
      headers: {'Authorization': 'header-secret'},
    );
    final failure = DioException(requestOptions: request, error: StateError('inner reason'));
    await sink.capture(
      createLog().observation(
        LogLevel.error,
        'Dio operation',
        error: failure,
        stackTrace: StackTrace.fromString('#0 refresh (package:mobile/sync.dart:12:3)'),
      ),
    );
    expect(transport.events, hasLength(1));
    final result = SentryEvent.fromJson(transport.events.single);
    expect(result.exceptions!.length, greaterThanOrEqualTo(2));
    expect(result.exceptions!.map((entry) => entry.type), containsAll(['StateError', 'DioException']));
    expect(result.exceptions!.any((entry) => entry.value!.contains('inner reason')), isTrue);
    expect(jsonEncode(transport.events), isNot(contains('query-secret')));
    expect(request.data, {'password': 'body-secret'});
    expect(request.headers['Authorization'], 'header-secret');
    dio.close();
  });

  test('bind and clear replace user and device context', () async {
    final transport = RecordingTransport();
    final sink = createSink();
    await initializeTestSentry(sink, transport);
    await sink.bindUser(id: 'user', email: 'user@example.com');
    await sink.bindDevice(connectedDeviceId: 'connected', platformDeviceId: 'platform');
    await Sentry.configureScope((scope) {
      expect(scope.user?.id, 'user');
    });
    await sink.capture(createLog().observation(LogLevel.error, 'bound'));
    expect(transport.events.first, contains('user'));

    await sink.clearUser();
    await sink.clearDevice();
    await sink.capture(createLog().observation(LogLevel.error, 'cleared'));
    expect((transport.events.first['user'] as Map)['id'], 'user');
    expect((transport.events.first['tags'] as Map)['connected_device_id'], 'connected');
    expect(transport.events.last['user'], isNull);
    expect((transport.events.last['tags'] as Map).containsKey('connected_device_id'), isFalse);
  });
}

SentryEvent event({int line = 12, String message = 'sync profile', Object? throwable}) => SentryEvent(
  throwable: throwable,
  message: SentryMessage(message),
  transaction: 'ProfileRoute',
  exceptions: [
    SentryException(
      type: 'StateError',
      value: 'original reason',
      stackTrace: SentryStackTrace(
        frames: [
          SentryStackFrame(inApp: true, fileName: 'outer.dart', function: 'outer', lineNo: 1),
          SentryStackFrame(inApp: true, fileName: 'sync.dart', function: 'refresh', lineNo: line),
        ],
      ),
    ),
  ],
);

final class SignatureFailure extends DomainError {
  const SignatureFailure({super.message, super.cause});
  @override
  String get typeIdentifier => 'SignatureFailure';
}

final class ThrowingHistory implements ObservationHistory {
  @override
  List<Observation> last({required int limit, LogLevel minimumLevel = LogLevel.verbose}) => throw StateError('history');
}
