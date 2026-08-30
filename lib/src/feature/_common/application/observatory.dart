import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:observatory/src/core/package_context.dart';
import 'package:observatory/src/feature/_common/application/bind_device.dart';
import 'package:observatory/src/feature/_common/application/bind_user.dart';
import 'package:observatory/src/feature/_common/application/capture_incident.dart';
import 'package:observatory/src/feature/_common/application/record_observation.dart';
import 'package:observatory/src/feature/_common/application/silent_ports.dart';
import 'package:observatory/src/feature/_common/data/sentry/sentry_incident_sink.dart';
import 'package:observatory/src/feature/_common/data/talker/bloc_observer/observer.dart';
import 'package:observatory/src/feature/_common/data/talker/http_logger/interceptor.dart';
import 'package:observatory/src/feature/_common/data/talker/talker_observation_log.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

final class Observatory {
  static Observatory? _instance;

  static Observatory get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('Observatory.start() was not called');
    }
    return instance;
  }

  static bool get isStarted => _instance?._hooksInstalled ?? false;

  final ObservatoryThread thread;
  final String zoneName;
  final ObservationClock clock;
  final RecordObservation _recordUseCase;
  final CaptureIncident _captureUseCase;
  final BindUser _bindUser;
  final BindDevice _bindDevice;
  final Talker? _talker;
  final SentryIncidentSink? _sentrySink;

  bool _hooksInstalled = false;

  Observatory._({
    required this.thread,
    required this.zoneName,
    required this.clock,
    required ObservationLog log,
    required IncidentSink sink,
    required ObservationFilter filter,
    required Talker? talker,
    required SentryIncidentSink? sentrySink,
  }) : _talker = talker,
       _sentrySink = sentrySink,
       _recordUseCase = RecordObservation(log: log, filter: filter),
       _captureUseCase = CaptureIncident(log: log, sink: sink),
       _bindUser = BindUser(sink: sink),
       _bindDevice = BindDevice(sink: sink);

  static void start({
    required ObservatoryThread thread,
    required String zoneName,
    ObservationClock clock = const SystemObservationClock(),
  }) {
    if (_instance != null) {
      throw StateError('Observatory.start() was already called');
    }

    final talker = dependencies.talker;
    final ObservationLog observationLog;
    final ObservationHistory history;
    if (talker == null) {
      const silent = SilentObservationLog();
      observationLog = silent;
      history = silent;
    } else {
      final talkerLog = TalkerObservationLog(
        talker: talker,
        filter: config.filter,
      );
      observationLog = talkerLog;
      history = talkerLog;
    }

    final sentrySink = config.sentry.enabled
        ? SentryIncidentSink(
            spec: config.sentry,
            history: history,
            dedupe: DedupePolicy(
              ttl: config.sentry.dedupeTtl,
              maxEntries: config.sentry.dedupeMaxEntries,
              clock: clock,
            ),
          )
        : null;

    _instance = Observatory._(
      thread: thread,
      zoneName: IsolateContext.normalizeZoneName(zoneName),
      clock: clock,
      log: observationLog,
      sink: sentrySink ?? const SilentIncidentSink(),
      filter: config.filter,
      talker: talker,
      sentrySink: sentrySink,
    );
  }

  @visibleForTesting
  static void reset() {
    _instance = null;
  }

  static List<NavigatorObserver> get navigatorObservers {
    return instance._navigatorObservers;
  }

  List<NavigatorObserver> get _navigatorObservers {
    return [
      if (config.sentry.enabled) SentryNavigatorObserver(),
      if (_talker != null) TalkerRouteObserver(_talker),
    ];
  }

  static void record(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    instance._record(level, message, error: error, stackTrace: stackTrace);
  }

  static Future<void> capture(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    return instance._capture(level, message, error: error, stackTrace: stackTrace);
  }

  static Future<void> bindUser({
    String? id,
    String? email,
  }) {
    return instance._bindUser(id: id, email: email);
  }

  static Future<void> clearUser() {
    return instance._bindUser.clear();
  }

  static Future<void> bindDevice({
    String? connectedDeviceId,
    String? platformDeviceId,
  }) {
    return instance._bindDevice(
      connectedDeviceId: connectedDeviceId,
      platformDeviceId: platformDeviceId,
    );
  }

  static Future<void> clearDevice() {
    return instance._bindDevice.clear();
  }

  static void attachTo(Dio dio) {
    instance._attachTo(dio);
  }

  static Widget logScreen({
    required String appBarTitle,
  }) {
    return instance._logScreen(appBarTitle: appBarTitle);
  }

  static Widget wrapApp({
    required Widget child,
  }) {
    return instance._wrapApp(child: child);
  }

  static Future<void> runZoned(FutureOr<void> Function() body) {
    return instance._runZoned(body);
  }

  void _record(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _recordUseCase(
      Observation(
        message: message,
        level: level,
        error: error,
        stackTrace: stackTrace,
        isolate: IsolateContext.fromZone(),
        time: clock.now(),
      ),
    );
  }

  Future<void> _capture(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    return _captureUseCase(
      Observation(
        message: message,
        level: level,
        error: error,
        stackTrace: stackTrace,
        isolate: IsolateContext.fromZone(),
        time: clock.now(),
      ),
    );
  }

  void _attachTo(Dio dio) {
    if (config.sentry.enabled) {
      dio.addSentry(captureFailedRequests: false);
    }
    final talker = _talker;
    if (talker != null) {
      dio.interceptors.add(
        SafeDioLogInterceptor(
          talker: talker,
          httpLog: config.httpLog,
          filter: config.filter,
        ),
      );
    }
  }

  Widget _logScreen({
    required String appBarTitle,
  }) {
    final talker = _talker;
    if (talker != null) {
      return TalkerScreen(
        talker: talker,
        appBarTitle: appBarTitle,
        isLogsExpanded: false,
        theme: TalkerScreenTheme.fromTheme(ThemeData.dark()),
      );
    }

    return _FallbackLogScreen(appBarTitle: appBarTitle);
  }

  Widget _wrapApp({
    required Widget child,
  }) {
    if (!config.sentry.enabled) {
      return child;
    }
    return SentryWidget(child: child);
  }

  Future<void> _runZoned(FutureOr<void> Function() body) {
    return Zone.current
        .fork(
          specification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) async {
              const op =
                  'Observatory.runZoned()'
                  '.Zone.current.fork().run<Future<void>>()'
                  '.handleUncaughtError():';

              if (!_hooksInstalled) {
                debugPrint('$op $error\n$stack');
              }

              await zone.run<Future<void>>(() async {
                await _capture(
                  LogLevel.critical,
                  'Unhandled error caught in global zone',
                  error: error,
                  stackTrace: stack,
                );
              });
            },
          ),
          zoneValues: <Object?, Object?>{
            IsolateContext.threadKey: thread,
            IsolateContext.zoneNameKey: zoneName,
          },
        )
        .run<Future<void>>(() async {
          await _installHooks();
          return await body();
        });
  }

  Future<void> _installHooks() async {
    if (_hooksInstalled) {
      return;
    }

    if (thread == ObservatoryThread.foreground) {
      if (config.sentry.enabled) {
        SentryWidgetsFlutterBinding.ensureInitialized();
      } else {
        WidgetsFlutterBinding.ensureInitialized();
      }
    }
    if (thread == ObservatoryThread.background) {
      DartPluginRegistrant.ensureInitialized();
    }

    final sentrySink = _sentrySink;
    if (sentrySink != null) {
      if (thread == ObservatoryThread.background) {
        await Sentry.init(sentrySink.applyBackgroundOptions);
      } else {
        await SentryFlutter.init(sentrySink.applyFlutterOptions);
      }
    }

    if (thread == ObservatoryThread.foreground) {
      FlutterError.onError = (errorDetails) async {
        await Observatory.capture(
          LogLevel.error,
          'FlutterError.onError(): Error: ${errorDetails.exception} \n StackTrace: ${errorDetails.stack}',
          error: errorDetails.exception,
          stackTrace: errorDetails.stack,
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          Observatory.capture(
            LogLevel.error,
            'PlatformDispatcher.instance.onError(): Error: $error \n StackTrace: $stack',
            error: error,
            stackTrace: stack,
          ),
        );
        return true;
      };
    }

    final talker = _talker;
    if (talker != null) {
      Bloc.observer = ObservatoryBlocObserver(
        talker: talker,
        config: config,
        capture: _captureUseCase,
        clock: clock,
      );
    }

    _hooksInstalled = true;
    Observatory.record(LogLevel.verbose, 'Observatory initialized');
  }
}

class _FallbackLogScreen extends StatelessWidget {
  final String appBarTitle;

  const _FallbackLogScreen({
    required this.appBarTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: const Center(
        child: Text('Observatory talker is not configured'),
      ),
    );
  }
}
