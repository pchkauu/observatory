import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:launch_mode/launch_mode.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/feature/_common/application/runtime.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:package_context/package_context.dart' as package_context;
import 'package:talker_flutter/talker_flutter.dart' show Talker;

/// One logging runtime per isolate. Run each isolate's entry point through [run].
abstract final class Observatory {
  static ObservatoryRuntime? _runtime;
  static final _packageContext = package_context.PackageContext<Config, _RuntimeDependencies>();
  static ObservatoryRuntime get _instance => _runtime ?? (throw StateError('Observatory.run() was not called'));

  /// Starts Observatory and runs [body] inside its logging zone.
  ///
  /// Launch mode is detected synchronously. A second active run in the same
  /// isolate completes with [StateError]. Errors from [body] retain their
  /// original object and stack trace.
  static Future<T> run<T>({
    required Config config,
    required String zoneName,
    required FutureOr<T> Function() body,
    ObservationClock clock = const SystemObservationClock(),
  }) {
    if (_runtime != null) return Future.error(StateError('Observatory is already running'));
    LaunchMode.initializeAutomatically();
    final graph = package_context.PackageGraph(config: config, dependencies: _RuntimeDependencies(clock));
    if (_packageContext.isInitialized) {
      _packageContext.refresh(graph);
    } else {
      _packageContext.initialize(graph);
    }
    final runtime = ObservatoryRuntime(
      config: _packageContext.config,
      clock: _packageContext.dependencies.clock,
      isolate: IsolateContext(launchMode: LaunchMode.current, zoneName: IsolateContext.normalizeZoneName(zoneName)),
    );
    _runtime = runtime;
    return runtime.run(body);
  }

  /// Whether the local logging runtime completed initialization.
  static bool get isStarted => _runtime?.started ?? false;

  /// Whether Sentry initialized successfully for the current runtime.
  static bool get isSentryEnabled => _runtime?.sentryActive ?? false;

  /// Managed Talker shared by Observatory integrations in this isolate.
  static Talker get talker => _instance.talker;

  /// Stable navigation observers for the current runtime.
  static List<NavigatorObserver> get navigatorObservers => _instance.navigatorObservers;

  /// Runs [body] with [zoneName] while retaining the current launch mode.
  static T runInZone<T>(String zoneName, T Function() body) => _instance.runInZone(zoneName, body);

  /// Writes one ordinary local record without remote incident capture.
  static void record(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final runtime = _instance;
    runtime.talker.write(runtime.talker.observation(level, message, error: error, stackTrace: stackTrace));
  }

  /// Writes one local incident and attempts remote capture when Sentry is active.
  static Future<void> capture(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final runtime = _instance;
    return runtime.capture(runtime.talker.observation(level, message, error: error, stackTrace: stackTrace));
  }

  /// Binds optional user identity fields to later Sentry events.
  static Future<void> bindUser({String? id, String? email}) =>
      _instance.useSink((sink) => sink.bindUser(id: id, email: email));

  /// Removes the bound user from later Sentry events.
  static Future<void> clearUser() => _instance.useSink((sink) => sink.clearUser());

  /// Binds optional device identifiers to later Sentry events.
  static Future<void> bindDevice({String? connectedDeviceId, String? platformDeviceId}) => _instance.useSink(
    (sink) => sink.bindDevice(connectedDeviceId: connectedDeviceId, platformDeviceId: platformDeviceId),
  );

  /// Removes bound device identifiers from later Sentry events.
  static Future<void> clearDevice() => _instance.useSink((sink) => sink.clearDevice());

  /// Attaches idempotent Observatory and Sentry instrumentation to [dio].
  static void attachTo(Dio dio) => _instance.attachTo(dio);

  /// Closes owned resources and restores handlers installed by Observatory.
  ///
  /// Calling this method without an active runtime is a no-op.
  static Future<void> close() async {
    final runtime = _runtime;
    if (runtime == null) return;
    await runtime.close();
    if (identical(_runtime, runtime)) _runtime = null;
  }
}

final class _RuntimeDependencies extends package_context.PackageDependencies {
  final ObservationClock clock;

  const _RuntimeDependencies(this.clock);
}
