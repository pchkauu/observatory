import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/data/talker/http_logger/interceptor.dart';
import 'package:talker/talker.dart' hide LogLevel;

void main() {
  group('SafeDioLogInterceptor', () {
    test('does not log headers or bodies by default', () async {
      final talker = _createTalker();
      final dio = _createDio(
        talker: talker,
        httpLog: const HttpLogSpec(),
        adapter: const _RecordingAdapter(),
      );

      await dio.post<void>(
        '/v1/device/connect',
        data: {
          'name': 'Pixel 8',
          'firebaseToken': 'secret-fcm-token',
        },
        options: Options(
          headers: {
            'X-Api-Key': 'secret-api-key',
          },
        ),
      );

      final logs = _logsText(talker);

      expect(logs, isNot(contains('Headers:')));
      expect(logs, isNot(contains('Body:')));
      expect(logs, isNot(contains('secret-api-key')));
      expect(logs, isNot(contains('secret-fcm-token')));
    });

    test('detailed mode logs headers and body with redaction', () async {
      final talker = _createTalker();
      final dio = _createDio(
        talker: talker,
        httpLog: const HttpLogSpec.detailed(),
        adapter: const _RecordingAdapter(),
      );

      await dio.post<void>(
        '/v1/device/connect',
        data: {
          'name': 'Pixel 8',
          'firebaseToken': 'secret-fcm-token',
        },
        options: Options(
          headers: {
            'X-Api-Key': 'secret-api-key',
            'X-Request-Id': 'req-1',
          },
        ),
      );

      final logs = _logsText(talker);

      expect(logs, contains('Headers:'));
      expect(logs, contains('Body:'));
      expect(logs, contains('<redacted>'));
      expect(logs, contains('Pixel 8'));
      expect(logs, isNot(contains('secret-api-key')));
      expect(logs, isNot(contains('secret-fcm-token')));
    });

    test('respects excluded HTTP URL filters', () async {
      final talker = _createTalker();
      final dio = _createDio(
        talker: talker,
        httpLog: const HttpLogSpec.detailed(),
        filter: ObservationFilter(
          enabled: true,
          excludedLogs: const [],
          excludedHttpUrls: [RegExp('health')],
          excludedBlocTypes: const [],
        ),
        adapter: const _RecordingAdapter(),
      );

      await dio.get<void>('/health');

      expect(_logsText(talker), isNot(contains('/health')));
    });
  });
}

Talker _createTalker() {
  return Talker(
    settings: TalkerSettings(
      useConsoleLogs: false,
    ),
  );
}

Dio _createDio({
  required Talker talker,
  required HttpLogSpec httpLog,
  required HttpClientAdapter adapter,
  ObservationFilter filter = const ObservationFilter.disabled(),
}) {
  final dio =
      Dio(
          BaseOptions(baseUrl: 'https://api.example.com'),
        )
        ..httpClientAdapter = adapter
        ..interceptors.add(
          SafeDioLogInterceptor(
            talker: talker,
            httpLog: httpLog,
            filter: filter,
          ),
        );
  return dio;
}

String _logsText(Talker talker) {
  return talker.history.map((item) => item.generateTextMessage()).join('\n');
}

final class _RecordingAdapter implements HttpClientAdapter {
  const _RecordingAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
