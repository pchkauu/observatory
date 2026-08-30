import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:domain_error/domain_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/src/feature/_common/data/talker/error_classifier.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';

void main() {
  const classifier = FrameworkErrorClassifier();

  group('FrameworkErrorClassifier', () {
    test('adds failure type identifier to log messages', () {
      const failure = _SignatureFailure(message: 'signature mismatch');

      final formatted = ErrorIdentity.formatLogMessage(
        'Sync failed',
        error: failure,
        describedType: classifier.describe(failure),
        typeIdentifier: classifier.typeIdentifier(failure),
      );

      expect(formatted, contains('Sync failed'));
      expect(formatted, contains('failure.type_identifier=SignatureFailure'));
    });

    test('uses stable names for common non-failure errors', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/v1/alerts'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/v1/alerts'),
          statusCode: 503,
        ),
      );

      expect(classifier.describe(dioError), 'DioException(503)');
      expect(
        classifier.describe(PlatformException(code: 'camera_denied')),
        'PlatformException(camera_denied)',
      );
      expect(classifier.describe(const SocketException('offline')), 'SocketException');
      expect(classifier.describe(TimeoutException('slow')), 'TimeoutException');
    });
  });
}

final class _SignatureFailure extends DomainError {
  @override
  String get typeIdentifier => 'SignatureFailure';

  const _SignatureFailure({
    super.message,
  });
}
