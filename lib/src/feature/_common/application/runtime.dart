import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:launch_mode/launch_mode.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:observatory/src/feature/_common/infrastructure/log_sanitizer.dart';
import 'package:observatory/src/feature/_common/infrastructure/sentry/sentry_incident_sink.dart';
import 'package:observatory/src/feature/_common/infrastructure/talker/bloc_observer/observer.dart';
import 'package:observatory/src/feature/_common/infrastructure/talker/http_logger/interceptor.dart';
import 'package:observatory/src/feature/_common/infrastructure/talker/managed_talker.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart' show TalkerRouteObserver;

/// Owns logging integrations and lifecycle state for one isolate run.
final class ObservatoryRuntime {
  // A Flutter binding survives close. Reuse its zone when Observatory created it.
  static Zone? _bindingZone;
  static ObservatoryRuntime? _bindingRuntime;

  /// Immutable settings used by this runtime.
  final Config config;

  /// Startup launch mode and default zone name.
  final IsolateContext isolate;

  /// Clock used to timestamp logs and evaluate deduplication windows.
  final ObservationClock clock;

  /// Zone that receives protected console output from the managed logger.
  final Zone parentZone = Zone.current;

  /// Optional Sentry initializer used to replace SDK startup in tests.
  final Future<void> Function(SentryIncidentSink, {required LaunchModeType launchMode})? initializeSentry;
  final Completer<void> _initialized = Completer<void>();
  final Map<Dio, _DioAttachment> _attachments = Map.identity();
  final Set<Future<void>> _pending = {};

  /// Sanitizer shared by local and remote output paths.
  late final LogSanitizer sanitizer = LogSanitizer(config.redaction);

  /// Talker instance shared by every connected log source.
  late final ManagedTalker talker = ManagedTalker(
    clock: clock,
    context: currentContext,
    sanitizer: sanitizer,
    observationFilter: config.filter,
    historyLimit: config.historyLimit,
    output: _output,
    reportFailure: reportFailure,
  );

  /// Sentry adapter that prepares, sanitizes, and deduplicates incidents.
  late final SentryIncidentSink sink = SentryIncidentSink(
    spec: config.sentry,
    history: talker,
    dedupe: DedupePolicy(ttl: config.sentry.dedupeTtl, maxEntries: config.sentry.dedupeMaxEntries, clock: clock),
    sanitizer: sanitizer,
    context: currentContext,
    reportFailure: reportFailure,
  );

  /// Navigation observers configured for the detected launch mode.
  late final List<NavigatorObserver> navigatorObservers = List.unmodifiable([
    if (isolate.launchMode == LaunchModeType.foreground && sentryActive) SentryNavigatorObserver(),
    TalkerRouteObserver(talker),
  ]);

  /// Root logging zone used by [run] and callbacks entering from outside it.
  late final Zone zone;
  late DebugPrintCallback _previousPrint;
  late DebugPrintCallback _printHook;
  FlutterExceptionHandler? _previousFlutter;
  FlutterExceptionHandler? _flutterHook;
  bool Function(Object, StackTrace)? _previousPlatform;
  bool Function(Object, StackTrace)? _platformHook;
  BlocObserver? _previousBloc;
  late BlocObserver _blocHook;

  /// Whether local logging and integrations completed initialization.
  bool started = false;

  /// Whether this runtime successfully initialized and owns Sentry.
  bool sentryActive = false;
  bool _ownsSentry = false;
  bool _closed = false;
  bool _closing = false;
  bool _reporting = false;
  Future<void>? _closeFuture;

  /// Creates an unstarted runtime.
  ///
  /// Throws [ArgumentError] for invalid history, Sentry, or launch-mode values.
  ObservatoryRuntime({required this.config, required this.isolate, required this.clock, this.initializeSentry}) {
    if (config.historyLimit < 0) throw ArgumentError.value(config.historyLimit, 'historyLimit');
    if (isolate.launchMode == LaunchModeType.unspecified) {
      throw ArgumentError.value(isolate.launchMode, 'launchMode', 'Must be initialized');
    }
    config.sentry.validate();
  }

  /// Resolves launch mode and zone name at the current event origin.
  IsolateContext currentContext() => IsolateContext.fromZone(Zone.current, isolate);

  /// Initializes integrations and executes [body] in the runtime zone.
  ///
  /// Errors from [body] are recorded and returned with their original stack.
  Future<T> run<T>(FutureOr<T> Function() body) {
    final result = Completer<T>();
    var ownsBindingZone = false;
    if (isolate.launchMode == LaunchModeType.foreground) {
      try {
        WidgetsBinding.instance;
      } on Object {
        ownsBindingZone = true;
      }
      ownsBindingZone = ownsBindingZone || _bindingZone != null;
    }
    if (ownsBindingZone) _bindingRuntime = this;
    final activeRuntime = ownsBindingZone ? () => _bindingRuntime : () => this;
    zone =
        (ownsBindingZone ? _bindingZone : null) ??
        parentZone.fork(
          zoneValues: {IsolateContext.contextKey: () => activeRuntime()?.isolate ?? const IsolateContext.unspecified()},
          specification: ZoneSpecification(
            print: (self, parent, origin, message) {
              final runtime = activeRuntime();
              if (runtime == null || runtime._closed) {
                parent.print(origin, message);
                return;
              }
              runtime.talker.write(
                Observation(
                  message: message,
                  level: LogLevel.info,
                  isolate: IsolateContext.fromZone(origin, runtime.isolate),
                  time: runtime.clock.now(),
                ),
              );
            },
            handleUncaughtError: (self, parent, origin, error, stack) {
              final runtime = activeRuntime();
              if (runtime == null || runtime._closed) {
                parent.handleUncaughtError(origin, error, stack);
                return;
              }
              unawaited(
                runtime.capture(
                  Observation(
                    message: 'Unhandled zone error',
                    level: LogLevel.critical,
                    error: error,
                    stackTrace: stack,
                    isolate: IsolateContext.fromZone(origin, runtime.isolate),
                    time: runtime.clock.now(),
                  ),
                ),
              );
            },
          ),
        );
    if (ownsBindingZone) _bindingZone = zone;
    zone.run<void>(() {
      unawaited(() async {
        try {
          try {
            await _initialize();
          } finally {
            _initialized.complete();
          }
          if (_closing) throw StateError('Observatory closed during initialization');
          final value = await body();
          result.complete(value);
        } on Object catch (error, stack) {
          await capture(
            talker.observation(LogLevel.critical, 'Observatory body failed', error: error, stackTrace: stack),
          );
          result.completeError(error, stack);
        }
      }());
    });
    return result.future;
  }

  /// Runs [body] in a child zone named [zoneName].
  ///
  /// Throws [StateError] after shutdown begins.
  T runInZone<T>(String zoneName, T Function() body) {
    if (_closed || _closing) throw StateError('Observatory is closed');
    // Keep the current async/error zone when nested; callbacks outside it enter the runtime zone.
    final base = Zone.current[IsolateContext.contextKey] == null ? zone : Zone.current;
    return base.fork(zoneValues: {IsolateContext.zoneNameKey: IsolateContext.normalizeZoneName(zoneName)}).run(body);
  }

  void _output(String message) => parentZone.print(message);

  /// Writes an internal telemetry failure without re-entering capture.
  void reportFailure(String message) {
    if (_reporting) return;
    _reporting = true;
    try {
      _output(currentContext().format(message));
    } on Object {
      // The final output channel may itself be unavailable.
    } finally {
      _reporting = false;
    }
  }

  Future<void> _initialize() async {
    _previousPrint = debugPrint;
    _printHook = (message, {wrapWidth}) {
      final text = message ?? 'null';
      final wrapped = wrapWidth != null && wrapWidth > 0
          ? text.split('\n').expand((line) => line.trim().isEmpty ? [line] : debugWordWrap(line, wrapWidth)).join('\n')
          : text;
      talker.write(talker.observation(LogLevel.info, wrapped));
    };
    debugPrint = _printHook;
    if (isolate.launchMode == LaunchModeType.foreground) {
      if (config.sentry.enabled) {
        SentryWidgetsFlutterBinding.ensureInitialized();
      } else {
        WidgetsFlutterBinding.ensureInitialized();
      }
    } else if (isolate.launchMode == LaunchModeType.background) {
      DartPluginRegistrant.ensureInitialized();
    }
    if (config.sentry.enabled) {
      try {
        if (Sentry.isEnabled) throw StateError('Sentry is already owned by the host');
        _ownsSentry = true;
        final initialize = initializeSentry;
        if (initialize != null) {
          await initialize(sink, launchMode: isolate.launchMode);
        } else {
          switch (isolate.launchMode) {
            case LaunchModeType.foreground:
              await SentryFlutter.init(sink.applyFlutterOptions);
            case LaunchModeType.background || LaunchModeType.isolate:
              await Sentry.init(sink.applyBackgroundOptions);
            case LaunchModeType.unspecified:
              throw StateError('Launch mode is not initialized');
          }
        }
        sentryActive = Sentry.isEnabled;
      } on Object {
        if (_ownsSentry) {
          try {
            await Sentry.close();
          } on Object {
            reportFailure('Sentry cleanup failed');
          }
          _ownsSentry = false;
        }
        talker.record(
          talker.observation(LogLevel.warning, 'Sentry initialization failed; local logging remains available'),
        );
      }
    }
    if (isolate.launchMode == LaunchModeType.foreground) {
      _previousFlutter = FlutterError.onError;
      _flutterHook = (details) {
        // The saved Sentry handler owns remote capture; this wrapper adds only the local record.
        talker.record(
          talker.observation(LogLevel.error, 'Flutter error', error: details.exception, stackTrace: details.stack),
        );
        _previousFlutter?.call(details);
      };
      FlutterError.onError = _flutterHook;
      _previousPlatform = PlatformDispatcher.instance.onError;
      _platformHook = (error, stack) {
        talker.record(talker.observation(LogLevel.critical, 'Platform error', error: error, stackTrace: stack));
        return _previousPlatform?.call(error, stack) ?? false;
      };
      PlatformDispatcher.instance.onError = _platformHook;
    }
    _previousBloc = Bloc.observer;
    _blocHook = ObservatoryBlocObserver(
      log: talker,
      filter: config.filter,
      effectsSettings: config.blocEffects,
      capture: capture,
      previous: _previousBloc!,
    );
    Bloc.observer = _blocHook;
    started = true;
  }

  /// Records [observation] locally and sends it when Sentry is active.
  Future<void> capture(Observation observation) async {
    if (_closed) return;
    try {
      talker.record(observation);
    } on Object {
      reportFailure('Incident logging failed');
    }
    await useSink((sink) => sink.capture(observation));
  }

  /// Runs [action] against active Sentry and tracks it for orderly shutdown.
  Future<void> useSink(Future<void> Function(SentryIncidentSink) action) {
    if (!sentryActive || _closed || _closing) return Future.value();
    final operation = () async {
      try {
        await action(sink);
      } on Object {
        reportFailure('Sentry operation failed');
      }
    }();
    _pending.add(operation);
    unawaited(operation.whenComplete(() => _pending.remove(operation)));
    return operation;
  }

  /// Attaches one safe logging interceptor and optional Sentry adapter to [dio].
  ///
  /// Repeated calls for the same client are ignored. Calls during or after
  /// shutdown throw [StateError].
  void attachTo(Dio dio) {
    if (_closed || _closing) throw StateError('Observatory is closed');
    if (_attachments.containsKey(dio)) return;
    final adapter = dio.httpClientAdapter;
    final transformer = dio.transformer;
    if (sentryActive) dio.addSentry(captureFailedRequests: false);
    final interceptor = SafeDioLogInterceptor(
      log: talker,
      spec: config.httpLog,
      filter: config.filter,
      sanitizer: sanitizer,
      reportFailure: reportFailure,
    );
    dio.interceptors.add(interceptor);
    _attachments[dio] = _DioAttachment(interceptor, adapter, transformer, dio.httpClientAdapter, dio.transformer);
  }

  /// Restores owned handlers, detaches clients, and closes pending resources.
  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    await _initialized.future;
    started = false;
    if (identical(debugPrint, _printHook)) debugPrint = _previousPrint;
    if (isolate.launchMode == LaunchModeType.foreground) {
      if (identical(FlutterError.onError, _flutterHook)) FlutterError.onError = _previousFlutter;
      if (identical(PlatformDispatcher.instance.onError, _platformHook)) {
        PlatformDispatcher.instance.onError = _previousPlatform;
      }
    }
    if (_previousBloc != null && identical(Bloc.observer, _blocHook)) Bloc.observer = _previousBloc!;
    for (final entry in _attachments.entries) {
      final dio = entry.key;
      final attachment = entry.value;
      dio.interceptors.remove(attachment.interceptor);
      if (identical(dio.httpClientAdapter, attachment.installedAdapter)) dio.httpClientAdapter = attachment.adapter;
      if (identical(dio.transformer, attachment.installedTransformer)) dio.transformer = attachment.transformer;
    }
    _attachments.clear();
    await Future.wait(_pending.toList());
    if (_ownsSentry) {
      try {
        await Sentry.close();
      } on Object {
        reportFailure('Sentry cleanup failed');
      }
    }
    sentryActive = false;
    _closed = true;
    if (identical(_bindingRuntime, this)) _bindingRuntime = null;
    await talker.close();
  }
}

final class _DioAttachment {
  final SafeDioLogInterceptor interceptor;
  final HttpClientAdapter adapter;
  final Transformer transformer;
  final HttpClientAdapter installedAdapter;
  final Transformer installedTransformer;
  const _DioAttachment(
    this.interceptor,
    this.adapter,
    this.transformer,
    this.installedAdapter,
    this.installedTransformer,
  );
}
