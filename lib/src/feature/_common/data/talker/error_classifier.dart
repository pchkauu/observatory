import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:domain_error/domain_error.dart';
import 'package:flutter/services.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class FrameworkErrorClassifier {
  const FrameworkErrorClassifier();

  String? describe(Object? error) {
    if (error == null) {
      return null;
    }
    if (error is DomainError) {
      return error.toString();
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status != null ? 'DioException($status)' : 'DioException';
    }
    if (error is PlatformException) {
      final code = error.code.trim();
      return code.isNotEmpty ? 'PlatformException($code)' : 'PlatformException';
    }
    if (error is SocketException) {
      return 'SocketException';
    }
    if (error is HandshakeException) {
      return 'HandshakeException';
    }
    if (error is TimeoutException) {
      return 'TimeoutException';
    }
    return ErrorIdentity.describeUnknown(error);
  }

  String? typeIdentifier(Object? error) {
    if (error is DomainError) {
      return error.typeIdentifier;
    }
    if (error is DioException) {
      return typeIdentifier(error.error);
    }
    return null;
  }
}
