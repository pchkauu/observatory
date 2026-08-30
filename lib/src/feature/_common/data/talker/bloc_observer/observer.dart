import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/feature/_common/application/capture_incident.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

class ObservatoryBlocObserver extends TalkerBlocObserver {
  final Config _config;
  final CaptureIncident _capture;
  final ObservationClock _clock;

  ObservatoryBlocObserver({
    required Talker talker,
    required Config config,
    required CaptureIncident capture,
    required ObservationClock clock,
    super.settings = const TalkerBlocLoggerSettings(
      printChanges: true,
      printClosings: true,
      printCreations: true,
    ),
  }) : _config = config,
       _capture = capture,
       _clock = clock,
       super(talker: talker);

  bool _shouldSkipBlocType(String blocType) {
    if (_config.disabledBlocLogs.any(blocType.contains)) {
      return true;
    }
    return !_config.filter.allowsBlocType(blocType);
  }

  String _blocTypeName(BlocBase<dynamic> bloc) {
    // Config matches Bloc types by substring. The runtime type name is the
    // only stable token the host can list in disabledBlocLogs / filter.
    // ignore: avoid_type_to_string, no_runtimeType_toString
    return bloc.runtimeType.toString().trim();
  }

  @override
  void onError(
    BlocBase<dynamic> bloc,
    Object error,
    StackTrace stackTrace,
  ) {
    const op = 'ObservatoryBlocObserver.onError():';
    unawaited(
      _capture(
        Observation(
          message: '$op $bloc - $error \n $stackTrace',
          level: LogLevel.error,
          error: error,
          stackTrace: stackTrace,
          isolate: IsolateContext.fromZone(),
          time: _clock.now(),
        ),
      ),
    );
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onChange(
    BlocBase<dynamic> bloc,
    Change<dynamic> change,
  ) {
    if (_shouldSkipBlocType(_blocTypeName(bloc))) {
      return;
    }
    super.onChange(bloc, change);
  }

  @override
  void onEvent(
    Bloc<dynamic, dynamic> bloc,
    Object? event,
  ) {
    if (_shouldSkipBlocType(_blocTypeName(bloc))) {
      return;
    }
    super.onEvent(bloc, event);
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    if (_shouldSkipBlocType(_blocTypeName(bloc))) {
      return;
    }
    super.onTransition(bloc, transition);
  }
}
