import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/data/error_classifier.dart';
import 'package:observatory/src/data/log_sanitizer.dart';
import 'package:observatory/src/domain/_barrel.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final class SentryIncidentSink implements IncidentSink {
  final SentrySpec spec;
  final ObservationHistory history;
  final FrameworkErrorClassifier classifier;
  final DedupePolicy dedupe;
  final LogSanitizer sanitizer;
  final IsolateContext Function() context;
  final void Function(String) reportFailure;
  final bool preferFileLine;

  SentryIncidentSink({
    required this.spec,
    required this.history,
    required this.dedupe,
    required this.sanitizer,
    required this.context,
    required this.reportFailure,
    this.classifier = const FrameworkErrorClassifier(),
    bool? preferFileLine,
  }) : preferFileLine = preferFileLine ?? kReleaseMode;

  void applyFlutterOptions(SentryFlutterOptions options) {
    applyBackgroundOptions(options);
    options
      ..attachScreenshot = spec.attachScreenshot
      ..screenshotQuality = SentryScreenshotQuality.low
      ..anrEnabled = spec.anrEnabled
      ..anrTimeoutInterval = spec.anrTimeoutInterval
      ..enableAppHangTracking = spec.enableAppHangTracking
      ..appHangTimeoutInterval = spec.appHangTimeoutInterval;
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
      ..enableDeduplication = false
      ..recordHttpBreadcrumbs = false
      ..beforeSend = beforeSend
      ..beforeSendTransaction = beforeSendTransaction
      ..beforeBreadcrumb = (breadcrumb, hint) => _breadcrumb(breadcrumb);
  }

  Future<SentryEvent?> beforeSend(SentryEvent event, Hint hint) async {
    try {
      final identity =
          classifier.typeIdentifier(event.throwable) ??
          event.exceptions
              ?.map((exception) => classifier.typeIdentifier(exception.throwable))
              .whereType<String>()
              .firstOrNull;
      final location = _deriveLocation(event);
      final isolate = _eventContext(event);
      event.tags = {
        ...?event.tags,
        'thread': isolate.thread.name,
        'zoneName': isolate.zoneName,
        'failure.type_identifier': ?identity,
      };
      event.contexts['observatory'] = {
        'thread': isolate.thread.name,
        'zoneName': isolate.zoneName,
        'location': ?location,
      };
      if (identity != null) event.contexts['failure'] = {'type_identifier': identity};
      final exception = event.exceptions?.firstOrNull;
      final message = event.message?.formatted ?? exception?.value ?? '';
      final fingerprint = jsonEncode([
        identity ?? exception?.type ?? 'Message',
        if (exception != null) location ?? '',
        sanitizer.text(message),
        if (exception == null) isolate.prefix,
      ]);
      _sanitizeEvent(event);
      if (hint.response != null) hint.response = SentryResponse.fromJson(_map(hint.response!.toJson()));
      final breadcrumbs = [...?event.breadcrumbs];
      if (spec.attachLogs) {
        try {
          final eligible = history.last(limit: spec.logsMaxBreadcrumbs, minimumLevel: spec.logsLevel);
          breadcrumbs.addAll(
            eligible.map(
              (log) => Breadcrumb(
                message: log.prefixedMessage,
                level: _toSentryLevel(log.level),
                timestamp: log.time,
                category: 'observatory',
                data: {'thread': log.isolate.thread.name, 'zoneName': log.isolate.zoneName},
              ),
            ),
          );
        } on Object {
          reportFailure('Log history is unavailable for Sentry');
        }
      }
      event.breadcrumbs = breadcrumbs
          .skip((breadcrumbs.length - spec.maxBreadcrumbs).clamp(0, breadcrumbs.length))
          .toList();
      if (!dedupe.allow(fingerprint)) return null;
      return event;
    } on Object {
      reportFailure('Sentry event preparation failed');
      final isolate = context();
      return SentryEvent(
        eventId: event.eventId,
        timestamp: event.timestamp,
        level: event.level,
        message: SentryMessage(sanitizer.text(event.message?.formatted ?? 'Incident details unavailable')),
        transaction: event.transaction == null ? null : sanitizer.text(event.transaction!),
        tags: {'thread': isolate.thread.name, 'zoneName': isolate.zoneName, 'observatory.preparation': 'failed'},
        exceptions: event.exceptions
            ?.map(
              (entry) => SentryException(
                type: entry.type == null ? null : sanitizer.text(entry.type!),
                value: entry.value == null ? null : sanitizer.text(entry.value!),
              ),
            )
            .toList(),
      );
    }
  }

  Future<SentryTransaction?> beforeSendTransaction(SentryTransaction event, Hint hint) async {
    try {
      _sanitizeEvent(event);
      for (final span in event.spans) {
        final data = _map(span.data);
        final tags = _map(span.tags).map((key, value) => MapEntry(key, value.toString()));
        span.data
          ..clear()
          ..addAll(data);
        span.tags
          ..clear()
          ..addAll(tags);
        final description = span.context.description;
        if (description != null) span.context.description = sanitizer.text(description);
      }
      return event;
    } on Object {
      reportFailure('Sentry transaction preparation failed');
      return null;
    }
  }

  Map<String, dynamic> _map(Map<String, dynamic> source) {
    final prepared = sanitizer.value(source);
    return prepared is Map<String, Object?> ? Map<String, dynamic>.from(prepared) : {'details': '<unavailable>'};
  }

  Breadcrumb? _breadcrumb(Breadcrumb? breadcrumb) {
    if (breadcrumb == null || breadcrumb is RouteObserverBreadcrumb) return null;
    try {
      final prepared = Breadcrumb.fromJson(_map(breadcrumb.toJson()));
      final existing = prepared.data;
      if (existing?['thread'] == null || existing?['zoneName'] == null) {
        final isolate = context();
        prepared.message = isolate.format(
          sanitizer.boundedMessage(prepared.message ?? '', prefixLength: isolate.prefix.length + 2),
        );
        prepared.data = {...?existing, 'thread': isolate.thread.name, 'zoneName': isolate.zoneName};
      }
      return prepared;
    } on Object {
      reportFailure('Breadcrumb preparation failed');
      return null;
    }
  }

  void _sanitizeEvent(SentryEvent event) {
    if (event.message != null) {
      final message = event.message!;
      final params = sanitizer.value(message.params);
      event.message = SentryMessage(
        sanitizer.text(message.formatted),
        template: message.template == null ? null : sanitizer.text(message.template!),
        params: params is List<Object?> ? params : null,
      );
    }
    if (event.request != null) {
      final request = event.request!;
      final fields = _map(request.toJson());
      if (request.queryString != null) {
        fields['query_string'] = sanitizer.clip(sanitizer.uri(Uri(query: request.queryString)).query);
      }
      event.request = SentryRequest.fromJson(fields);
    }
    event.contexts = Contexts.fromJson(_map(event.contexts.toJson()));
    // Sentry 9 still serializes this public field alongside contexts.
    // ignore: deprecated_member_use
    if (event.extra != null) event.extra = _map(event.extra!);
    event.tags = event.tags == null ? null : _map(event.tags!).map((key, value) => MapEntry(key, value.toString()));
    event.breadcrumbs = event.breadcrumbs?.map(_breadcrumb).whereType<Breadcrumb>().toList();
    event.exceptions = event.exceptions?.map((exception) {
      final fields = exception.toJson()..remove('stacktrace');
      return SentryException.fromJson(_map(fields))..stackTrace = _stackTrace(exception.stackTrace);
    }).toList();
    event.threads = event.threads?.map((thread) {
      // Preserve the SDK thread shape explicitly, including its nested stack trace.
      return SentryThread(
        id: thread.id,
        name: thread.name == null ? null : sanitizer.text(thread.name!),
        crashed: thread.crashed,
        current: thread.current,
        stacktrace: _stackTrace(thread.stacktrace),
      );
    }).toList();
    if (event.transaction != null) event.transaction = sanitizer.text(event.transaction!);
  }

  SentryStackTrace? _stackTrace(SentryStackTrace? stack) {
    if (stack == null) return null;
    // Bound stack processing from the nearest frame, keeping the SDK's oldest-first order.
    final prepared = sanitizer.value(stack.frames.reversed.map((frame) => frame.toJson()));
    final frames = <SentryStackFrame>[];
    for (final value in prepared is List<Object?> ? prepared : <Object?>[]) {
      if (value is! Map<String, Object?>) {
        frames.add(SentryStackFrame(function: LogSanitizer.truncated));
        continue;
      }
      final fields = Map<String, dynamic>.from(value);
      for (final key in ['pre_context', 'post_context']) {
        if (fields[key] is List<Object?>) {
          fields[key] = (fields[key] as List<Object?>).map((item) => item.toString()).toList();
        }
      }
      if (fields['frames_omitted'] is List<Object?>) {
        fields['frames_omitted'] = (fields['frames_omitted'] as List<Object?>).whereType<int>().toList();
      }
      frames.add(SentryStackFrame.fromJson(fields));
    }
    return SentryStackTrace(
      frames: frames.reversed.toList(),
      registers: _map(stack.registers).map((key, value) => MapEntry(key, value.toString())),
      lang: stack.lang == null ? null : sanitizer.text(stack.lang!),
      snapshot: stack.snapshot,
    );
  }

  IsolateContext _eventContext(SentryEvent event) {
    final thread = event.tags?['thread'];
    final zoneName = event.tags?['zoneName'];
    final fallback = context();
    return IsolateContext(
      thread: ObservatoryThread.values.where((value) => value.name == thread).firstOrNull ?? fallback.thread,
      zoneName: zoneName ?? fallback.zoneName,
    );
  }

  String? _deriveLocation(SentryEvent event) {
    // Sentry stores oldest frames first; inspect the nearest calls within a fixed budget.
    final frames = (event.exceptions ?? <SentryException>[])
        .expand((exception) => exception.stackTrace?.frames.reversed ?? <SentryStackFrame>[])
        .followedBy(
          (event.threads ?? <SentryThread>[]).expand(
            (thread) => thread.stacktrace?.frames.reversed ?? <SentryStackFrame>[],
          ),
        )
        .take(LogSanitizer.maxElements)
        .map(_toView)
        .toList();
    return ErrorIdentity.locationFrom(
      frames: frames,
      appPackageName: spec.appPackageName,
      preferFileLine: preferFileLine,
    );
  }

  @override
  Future<void> capture(Observation observation) async {
    if (!spec.enabled) return;
    await Sentry.captureEvent(
      SentryEvent(
        message: SentryMessage(sanitizer.text(observation.message)),
        throwable: observation.error,
        timestamp: observation.time,
        level: _toSentryLevel(observation.level),
        tags: {'thread': observation.isolate.thread.name, 'zoneName': observation.isolate.zoneName},
      ),
      stackTrace: observation.stackTrace,
    );
  }

  @override
  Future<void> bindUser({
    String? id,
    String? email,
  }) async {
    if (!spec.enabled || (id == null && email == null)) {
      return;
    }
    await Sentry.configureScope((scope) async {
      final user = scope.user ?? SentryUser(id: id, email: email);
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
