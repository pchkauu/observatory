import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/data/log_sanitizer.dart';
import 'package:observatory/src/data/talker/http_logger/interceptor.dart';
import 'package:talker/talker.dart' as talker;

import '../../support.dart';

void main() {
  for (final detailed in [false, true]) {
    test('HTTP request/response redact query, headers and payload; detailed=$detailed', () async {
      final log = createLog();
      final adapter = RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))..httpClientAdapter = adapter;
      dio.interceptors.add(
        SafeDioLogInterceptor(
          log: log,
          spec: detailed ? const HttpLogSpec.detailed() : const HttpLogSpec(),
          filter: const ObservationFilter.disabled(),
          sanitizer: const LogSanitizer(RedactionPolicy()),
          reportFailure: (_) {},
        ),
      );
      final body = {
        'name': 'phone',
        'nested': [
          {'token': 'body-secret'},
        ],
      };
      await dio.post<void>(
        '/profile?token=query-secret&public=ok',
        data: body,
        options: Options(headers: {'Authorization': 'header-secret'}),
      );
      final text = log.history.map((entry) => entry.generateTextMessage()).join('\n');
      expect(log.history, hasLength(2));
      for (final secret in ['body-secret', 'query-secret', 'header-secret', 'response-secret']) {
        expect(text, isNot(contains(secret)));
      }
      expect(text.contains('Body:'), detailed);
      expect(text.contains('Headers:'), detailed);
      expect(text, contains('public=ok'));
      expect(text.split('\n').every((line) => line.startsWith('foreground(main): ')), isTrue);
      expect(adapter.requests.single.uri.queryParameters['token'], 'query-secret');
      expect(adapter.requests.single.headers['Authorization'], 'header-secret');
      expect((body['nested']! as List).single, {'token': 'body-secret'});
      dio.close();
    });
  }

  test('excluded URLs produce no local records', () async {
    final log = createLog();
    final dio = Dio()..httpClientAdapter = RecordingAdapter();
    dio.interceptors.add(
      SafeDioLogInterceptor(
        log: log,
        spec: const HttpLogSpec.detailed(),
        filter: ObservationFilter(
          enabled: true,
          excludedLogs: const [],
          excludedHttpUrls: [RegExp('health')],
          excludedBlocTypes: const [],
        ),
        sanitizer: const LogSanitizer(RedactionPolicy()),
        reportFailure: (_) {},
      ),
    );
    await dio.get<void>('https://example.com/health');
    expect(log.history, isEmpty);
    dio.close();
  });

  test('logger failures preserve successful and failed HTTP results', () async {
    final log = createLog(output: (_) => throw StateError('output'))..configure(observer: ThrowingObserver());
    final adapter = RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(
      SafeDioLogInterceptor(
        log: log,
        spec: const HttpLogSpec.detailed(),
        filter: const ObservationFilter.disabled(),
        sanitizer: const LogSanitizer(RedactionPolicy()),
        reportFailure: (_) {},
      ),
    );
    expect((await dio.get<void>('https://example.com/ok')).statusCode, 200);
    adapter.status = 503;
    await expectLater(dio.get<void>('https://example.com/fail'), throwsA(isA<DioException>()));
    expect(adapter.requests, hasLength(2));
    expect(log.history, hasLength(4));
    dio.close();
  });
}

final class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'ok': true, 'token': 'response-secret'}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class ThrowingObserver extends talker.TalkerObserver {
  @override
  void onLog(talker.TalkerData log) => throw StateError('observer');
}
