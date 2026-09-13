import 'package:dio/dio.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/data/log_sanitizer.dart';
import 'package:observatory/src/data/talker/managed_talker.dart';
import 'package:observatory/src/domain/_barrel.dart';
import 'package:talker/talker.dart' as talker;

final class SafeDioLogInterceptor extends Interceptor {
  final ManagedTalker log;
  final HttpLogSpec spec;
  final ObservationFilter filter;
  final LogSanitizer sanitizer;
  final void Function(String) reportFailure;

  SafeDioLogInterceptor({
    required this.log,
    required this.spec,
    required this.filter,
    required this.sanitizer,
    required this.reportFailure,
  }) {
    log.settings.registerKeys([
      talker.TalkerKey.httpRequest,
      talker.TalkerKey.httpResponse,
      talker.TalkerKey.httpError,
    ]);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      _write(options, talker.TalkerKey.httpRequest, headers: options.headers, body: options.data);
    } on Object {
      reportFailure('HTTP request logging failed');
    } finally {
      handler.next(options);
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      _write(
        response.requestOptions,
        talker.TalkerKey.httpResponse,
        headers: response.headers.map,
        body: response.data,
        status: response.statusCode,
      );
    } on Object {
      reportFailure('HTTP response logging failed');
    } finally {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      _write(
        err.requestOptions,
        talker.TalkerKey.httpError,
        headers: err.response?.headers.map,
        body: err.response?.data,
        status: err.response?.statusCode,
        message: err.message,
        level: LogLevel.error,
      );
    } on Object {
      reportFailure('HTTP error logging failed');
    } finally {
      handler.next(err);
    }
  }

  void _write(
    RequestOptions options,
    String key, {
    Object? headers,
    Object? body,
    int? status,
    String? message,
    LogLevel level = LogLevel.debug,
  }) {
    if (!filter.allowsHttpUrl(options.uri)) return;
    final buffer = StringBuffer('[${options.method}] ${sanitizer.uri(options.uri)}');
    if (status != null) buffer.write('\nStatus: $status');
    if (message != null) buffer.write('\nMessage: ${sanitizer.text(message)}');
    if (spec.printHeaders && headers != null) buffer.write('\nHeaders: ${sanitizer.encode(headers)}');
    if (spec.printBody && body != null) buffer.write('\nBody: ${sanitizer.encode(body)}');
    log.write(log.observation(level, sanitizer.clip(buffer.toString())), key: key);
  }
}
