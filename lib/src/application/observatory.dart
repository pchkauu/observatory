import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:observatory/src/application/runtime.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/domain/_barrel.dart';
import 'package:talker_flutter/talker_flutter.dart' show Talker;

/// One logging runtime per isolate. Run each isolate's entry point through [run].
abstract final class Observatory {
  static ObservatoryRuntime? _runtime;
  static ObservatoryRuntime get _instance => _runtime ?? (throw StateError('Observatory.run() was not called'));

  static Future<T> run<T>({
    required Config config,
    required ObservatoryThread thread,
    required String zoneName,
    required FutureOr<T> Function() body,
    ObservationClock clock = const SystemObservationClock(),
  }) {
    if (_runtime != null) return Future.error(StateError('Observatory is already running'));
    final runtime = ObservatoryRuntime(
      config: config,
      clock: clock,
      isolate: IsolateContext(thread: thread, zoneName: IsolateContext.normalizeZoneName(zoneName)),
    );
    _runtime = runtime;
    return runtime.run(body);
  }

  static bool get isStarted => _runtime?.started ?? false;
  static bool get isSentryEnabled => _runtime?.sentryActive ?? false;
  static Talker get talker => _instance.talker;
  static List<NavigatorObserver> get navigatorObservers => _instance.navigatorObservers;

  static T runInZone<T>(String zoneName, T Function() body) => _instance.runInZone(zoneName, body);

  static void record(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final runtime = _instance;
    runtime.talker.write(runtime.talker.observation(level, message, error: error, stackTrace: stackTrace));
  }

  static Future<void> capture(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final runtime = _instance;
    return runtime.capture(runtime.talker.observation(level, message, error: error, stackTrace: stackTrace));
  }

  static Future<void> bindUser({String? id, String? email}) =>
      _instance.useSink((sink) => sink.bindUser(id: id, email: email));
  static Future<void> clearUser() => _instance.useSink((sink) => sink.clearUser());
  static Future<void> bindDevice({String? connectedDeviceId, String? platformDeviceId}) => _instance.useSink(
    (sink) => sink.bindDevice(connectedDeviceId: connectedDeviceId, platformDeviceId: platformDeviceId),
  );
  static Future<void> clearDevice() => _instance.useSink((sink) => sink.clearDevice());
  static void attachTo(Dio dio) => _instance.attachTo(dio);

  static Future<void> close() async {
    final runtime = _runtime;
    if (runtime == null) return;
    await runtime.close();
    if (identical(_runtime, runtime)) _runtime = null;
  }
}
