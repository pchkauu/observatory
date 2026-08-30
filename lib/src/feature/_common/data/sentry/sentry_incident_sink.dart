import 'package:flutter/foundation.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/feature/_common/data/talker/error_classifier.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final class SentryIncidentSink implements IncidentSink {
  final SentrySpec spec;
  final ObservationHistory history;
  final FrameworkErrorClassifier classifier;
  final DedupePolicy dedupe;
  final bool preferFileLine;

  SentryIncidentSink({
    required this.spec,
    required this.history,
    required this.dedupe,
    this.classifier = const FrameworkErrorClassifier(),
    bool? preferFileLine,
  }) : preferFileLine = preferFileLine ?? kReleaseMode;

  void applyFlutterOptions(SentryFlutterOptions options) {
    options
      ..dsn = spec.dsn
      ..environment = spec.environment
      ..release = spec.release
      ..dist = spec.dist
      ..sampleRate = spec.sampleRate
      ..tracesSampleRate = spec.sampleRate
      ..privacy.maskAllImages = false
      ..privacy.maskAllText = false
      ..privacy.maskAssetImages = false
      ..maxBreadcrumbs = spec.maxBreadcrumbs
      ..attachScreenshot = spec.attachScreenshot
      ..screenshotQuality = SentryScreenshotQuality.low
      ..maxRequestBodySize = MaxRequestBodySize.always
      ..anrEnabled = spec.anrEnabled
      ..anrTimeoutInterval = spec.anrTimeoutInterval
      ..enableAppHangTracking = spec.enableAppHangTracking
      ..appHangTimeoutInterval = spec.appHangTimeoutInterval
      ..beforeSend = beforeSend;
  }

  void applyBackgroundOptions(SentryOptions options) {
    options
      ..dsn = spec.dsn
      ..environment = spec.environment
      ..release = spec.release
      ..dist = spec.dist
      ..sampleRate = spec.sampleRate
      ..tracesSampleRate = spec.sampleRate
      ..maxBreadcrumbs = spec.maxBreadcrumbs
      ..maxRequestBodySize = MaxRequestBodySize.always
      ..beforeSend = beforeSend;
  }

  Future<SentryEvent?> beforeSend(
    SentryEvent event,
    Hint hint,
  ) async {
    final fingerprint = _fingerprint(event);
    if (!dedupe.allow(fingerprint)) {
      return null;
    }

    final withFailureContext = _annotateFailure(event);
    if (!spec.attachLogs) {
      return _retitleEvent(withFailureContext);
    }

    final logs = history.last(limit: spec.logsMaxBreadcrumbs);
    final breadcrumbs = logs.map((observation) {
      return Breadcrumb(
        message: ErrorIdentity.formatLogMessage(
          observation.message,
          error: observation.error,
          describedType: classifier.describe(observation.error),
          typeIdentifier: classifier.typeIdentifier(observation.error),
        ),
        level: _toSentryLevel(observation.level),
        timestamp: observation.time,
      );
    }).toList();

    withFailureContext.breadcrumbs = [...?withFailureContext.breadcrumbs, ...breadcrumbs];
    return _retitleEvent(withFailureContext);
  }

  @override
  Future<void> capture(Observation observation) async {
    if (!spec.enabled) {
      return;
    }
    await Sentry.captureException(
      observation.error,
      stackTrace: observation.stackTrace,
      withScope: (scope) async {
        scope.level = _toSentryLevel(observation.level);
      },
    );
  }

  @override
  Future<void> bindUser({
    String? id,
    String? email,
  }) async {
    if (!spec.enabled) {
      return;
    }
    await Sentry.configureScope((scope) async {
      final user = scope.user ?? SentryUser();
      if (id != null) {
        user.id = id;
      }
      if (email != null) {
        user.email = email;
      }
      await scope.setUser(user);
    });
  }

  @override
  Future<void> clearUser() async {
    if (!spec.enabled) {
      return;
    }
    await Sentry.configureScope((scope) async {
      await scope.setUser(null);
    });
  }

  @override
  Future<void> bindDevice({
    String? connectedDeviceId,
    String? platformDeviceId,
  }) async {
    if (!spec.enabled) {
      return;
    }
    await Sentry.configureScope((scope) async {
      final connected = connectedDeviceId?.trim();
      final platform = platformDeviceId?.trim();

      if (connected != null && connected.isNotEmpty) {
        await scope.setTag('connected_device_id', connected);
      } else {
        await scope.removeTag('connected_device_id');
      }

      if (platform != null && platform.isNotEmpty) {
        await scope.setTag('device_id', platform);
      } else {
        await scope.removeTag('device_id');
      }

      final context = <String, String>{
        if (connected != null && connected.isNotEmpty) 'connectedDeviceId': connected,
        if (platform != null && platform.isNotEmpty) 'deviceId': platform,
      };
      if (context.isEmpty) {
        await scope.removeContexts('observatory_device');
      } else {
        await scope.setContexts('observatory_device', context);
      }
    });
  }

  @override
  Future<void> clearDevice() async {
    if (!spec.enabled) {
      return;
    }
    await Sentry.configureScope((scope) async {
      await scope.removeTag('connected_device_id');
      await scope.removeTag('device_id');
      await scope.removeContexts('observatory_device');
    });
  }

  SentryEvent _annotateFailure(SentryEvent event) {
    final typeIdentifier = classifier.typeIdentifier(event.throwable) ?? _typeIdentifierFromExceptions(event);
    if (typeIdentifier == null) {
      return event;
    }

    return event
      ..tags = {
        ...?event.tags,
        'failure.type_identifier': typeIdentifier,
      }
      ..contexts['failure'] = {
        'type_identifier': typeIdentifier,
      };
  }

  String? _typeIdentifierFromExceptions(SentryEvent event) {
    final exceptions = event.exceptions;
    if (exceptions == null) {
      return null;
    }
    for (final exception in exceptions) {
      final typeIdentifier = classifier.typeIdentifier(exception.throwable);
      if (typeIdentifier != null) {
        return typeIdentifier;
      }
    }
    return null;
  }

  String _fingerprint(SentryEvent event) {
    final exception = event.exceptions?.isNotEmpty ?? false ? event.exceptions!.first : null;
    final type = exception?.type ?? classifier.describe(exception?.throwable) ?? 'Error';
    final value = exception?.value ?? _deriveLocation(event) ?? event.transaction ?? 'unknown';
    return '$type:$value';
  }

  SentryEvent _retitleEvent(SentryEvent event) {
    if (event.exceptions == null || (event.exceptions?.isEmpty ?? true)) {
      return event;
    }

    final location =
        _deriveLocation(event) ??
        ErrorIdentity.fallbackOperation(event.contexts.trace?.operation) ??
        'unknown_location';
    final stableType = classifier.describe(event.exceptions?.first.throwable) ?? 'Error';
    final updatedExceptions = event.exceptions?.map((ex) {
      return ex
        ..type = stableType
        ..value = location;
    }).toList();

    return event
      ..exceptions = updatedExceptions
      ..transaction = '$stableType -> $location';
  }

  String? _deriveLocation(SentryEvent event) {
    final frames = <StackFrameView>[];
    final exceptionFrames = event.exceptions?.first.stackTrace?.frames;
    if (exceptionFrames != null && exceptionFrames.isNotEmpty) {
      frames.addAll(exceptionFrames.map(_toView));
    }
    final threads = event.threads;
    if (threads != null) {
      for (final thread in threads) {
        final tf = thread.stacktrace?.frames;
        if (tf != null && tf.isNotEmpty) {
          frames.addAll(tf.map(_toView));
        }
      }
    }
    return ErrorIdentity.locationFrom(
      frames: frames,
      appPackageName: spec.appPackageName,
      preferFileLine: preferFileLine,
    );
  }

  static StackFrameView _toView(SentryStackFrame frame) {
    return StackFrameView(
      inApp: frame.inApp ?? false,
      package: frame.package,
      module: frame.module,
      absPath: frame.absPath,
      fileName: frame.fileName,
      function: frame.function,
      lineNo: frame.lineNo,
      colNo: frame.colNo,
    );
  }

  static SentryLevel _toSentryLevel(LogLevel level) {
    return switch (level) {
      LogLevel.verbose || LogLevel.debug => SentryLevel.debug,
      LogLevel.info => SentryLevel.info,
      LogLevel.warning => SentryLevel.warning,
      LogLevel.error => SentryLevel.error,
      LogLevel.critical => SentryLevel.fatal,
    };
  }
}
