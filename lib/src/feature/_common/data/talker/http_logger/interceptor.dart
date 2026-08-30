import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/feature/_common/data/talker/talker_observation_log.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

const _redactedValue = '<redacted>';
const _jsonEncoder = JsonEncoder.withIndent('  ');

final class SafeDioLogInterceptor extends Interceptor {
  final Talker _talker;
  final HttpLogSpec _httpLog;
  final ObservationFilter _filter;

  SafeDioLogInterceptor({
    required Talker talker,
    required HttpLogSpec httpLog,
    required ObservationFilter filter,
  }) : _talker = talker,
       _httpLog = httpLog,
       _filter = filter {
    _talker.settings.registerKeys(
      [
        TalkerKey.httpRequest,
        TalkerKey.httpResponse,
        TalkerKey.httpError,
      ],
    );
  }

  bool _shouldLogRequest(RequestOptions options) {
    return _filter.allowsHttpUrl(options.uri);
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (_shouldLogRequest(options)) {
      _logRequest(options);
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_shouldLogRequest(response.requestOptions)) {
      _logResponse(response);
    }
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (_shouldLogRequest(err.requestOptions)) {
      _logError(err);
    }
    handler.next(err);
  }

  void _logRequest(RequestOptions options) {
    final message = _HttpLogMessageBuilder(
      method: options.method,
      uri: options.uri,
      headers: options.headers,
      body: options.data,
      httpLog: _httpLog,
    ).build();

    _talker.logCustom(
      TalkerLog(
        message,
        key: TalkerKey.httpRequest,
        title: 'http-request',
        logLevel: toTalkerLogLevel(LogLevel.debug),
      ),
    );
  }

  void _logResponse(Response<dynamic> response) {
    final message = _HttpLogMessageBuilder(
      method: response.requestOptions.method,
      uri: response.requestOptions.uri,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers.map,
      body: response.data,
      httpLog: _httpLog,
    ).build();

    _talker.logCustom(
      TalkerLog(
        message,
        key: TalkerKey.httpResponse,
        title: 'http-response',
        logLevel: toTalkerLogLevel(LogLevel.debug),
      ),
    );
  }

  void _logError(DioException err) {
    final response = err.response;
    final message = _HttpLogMessageBuilder(
      method: err.requestOptions.method,
      uri: err.requestOptions.uri,
      statusCode: response?.statusCode,
      statusMessage: err.message,
      headers: response?.headers.map,
      body: response?.data,
      httpLog: _httpLog,
    ).build();

    _talker.logCustom(
      TalkerLog(
        message,
        key: TalkerKey.httpError,
        title: 'http-error',
        logLevel: toTalkerLogLevel(LogLevel.error),
      ),
    );
  }
}

final class _HttpLogMessageBuilder {
  final String method;
  final Uri uri;
  final int? statusCode;
  final String? statusMessage;
  final Map<String, Object?>? headers;
  final Object? body;
  final HttpLogSpec httpLog;

  const _HttpLogMessageBuilder({
    required this.method,
    required this.uri,
    required this.httpLog,
    this.statusCode,
    this.statusMessage,
    this.headers,
    this.body,
  });

  String build() {
    final buffer = StringBuffer('[$method] $uri');

    final code = statusCode;
    if (code != null) {
      buffer.write('\nStatus: $code');
    }

    final message = statusMessage;
    if (message != null && message.isNotEmpty) {
      buffer.write('\nMessage: $message');
    }

    if (httpLog.printHeaders && headers != null && headers!.isNotEmpty) {
      buffer.write('\nHeaders: ${_encode(_sanitizeHeaders(headers!))}');
    }

    if (httpLog.printBody && body != null) {
      buffer.write('\nBody: ${_encode(_sanitizeBody(body, isTopLevel: true))}');
    }

    return buffer.toString();
  }

  Map<String, Object?> _sanitizeHeaders(Map<String, Object?> source) {
    return source.map((key, value) {
      if (httpLog.redaction.isSensitiveHeader(key)) {
        return MapEntry(key, _redactedValue);
      }
      return MapEntry(key, value);
    });
  }

  Object? _sanitizeBody(
    Object? value, {
    required bool isTopLevel,
    String? key,
  }) {
    if (key != null && httpLog.redaction.isSensitiveBodyKey(key)) {
      return _redactedValue;
    }

    if (value == null || value is num || value is bool) {
      return value;
    }

    if (value is String) {
      if (isTopLevel && httpLog.redaction.enabled) {
        final decoded = _tryDecodeJson(value);
        if (decoded != null) {
          return _sanitizeBody(
            decoded,
            isTopLevel: false,
          );
        }
      }
      return value;
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is Uri) {
      return value.toString();
    }

    if (value is FormData) {
      return _sanitizeFormData(value);
    }

    if (value is MultipartFile) {
      return _multipartFileSummary(value);
    }

    if (value is Uint8List) {
      return '<bytes length=${value.length}>';
    }

    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final entryKey = entry.key?.toString() ?? 'null';
        result[entryKey] = _sanitizeBody(
          entry.value,
          isTopLevel: false,
          key: entryKey,
        );
      }
      return result;
    }

    if (value is Iterable<Object?>) {
      return value.map((item) {
        return _sanitizeBody(
          item,
          isTopLevel: false,
        );
      }).toList();
    }

    if (httpLog.redaction.enabled) {
      return '<${value.runtimeType}>';
    }
    return value.toString();
  }

  Map<String, Object?> _sanitizeFormData(FormData formData) {
    final fields = <String, Object?>{};
    for (final field in formData.fields) {
      fields[field.key] = _sanitizeBody(
        field.value,
        isTopLevel: false,
        key: field.key,
      );
    }

    final files = <String, Object?>{};
    for (final file in formData.files) {
      files[file.key] = _multipartFileSummary(file.value);
    }

    return {
      'fields': fields,
      'files': files,
    };
  }

  Map<String, Object?> _multipartFileSummary(MultipartFile file) {
    return {
      'filename': file.filename,
      'contentType': file.contentType?.toString(),
      'bytes': file.length,
    };
  }

  Object? _tryDecodeJson(String value) {
    try {
      return jsonDecode(value);
    } on Object {
      return null;
    }
  }

  String _encode(Object? value) {
    try {
      return _jsonEncoder.convert(value);
    } on Object {
      return value.toString();
    }
  }
}
