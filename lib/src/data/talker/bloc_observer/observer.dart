import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:observatory/src/data/talker/managed_talker.dart';
import 'package:observatory/src/domain/_barrel.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';

final class ObservatoryBlocObserver extends BlocObserver {
  final ManagedTalker log;
  final ObservationFilter filter;
  final Future<void> Function(Observation) capture;
  final BlocObserver previous;
  final TalkerBlocObserver _logs;

  ObservatoryBlocObserver({required this.log, required this.filter, required this.capture, required this.previous})
    : _logs = TalkerBlocObserver(
        talker: log,
        settings: const TalkerBlocLoggerSettings(printChanges: true, printCreations: true, printClosings: true),
      );

  bool _allows(BlocBase<dynamic> bloc) {
    // Matching by name is the public filter contract; obfuscated names need host-specific filters.
    // ignore: avoid_type_to_string, no_runtimeType_toString
    return filter.allowsBlocType(bloc.runtimeType.toString());
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    unawaited(capture(log.observation(LogLevel.error, 'Bloc error', error: error, stackTrace: stackTrace)));
    previous.onError(bloc, error, stackTrace);
  }

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    previous.onCreate(bloc);
    if (_allows(bloc)) _logs.onCreate(bloc);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    previous.onClose(bloc);
    if (_allows(bloc)) _logs.onClose(bloc);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    previous.onChange(bloc, change);
    if (_allows(bloc)) _logs.onChange(bloc, change);
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    previous.onEvent(bloc, event);
    if (_allows(bloc)) _logs.onEvent(bloc, event);
  }

  @override
  void onDone(Bloc<dynamic, dynamic> bloc, Object? event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(bloc, event, error, stackTrace);
    previous.onDone(bloc, event, error, stackTrace);
    if (_allows(bloc)) {
      // onError owns incident capture; completion adds only its operation record.
      // ignore: avoid_type_to_string, no_runtimeType_toString
      log.debug('Bloc ${bloc.runtimeType} completed event: ${log.sanitizer.encode(event)}');
    }
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    previous.onTransition(bloc, transition);
    if (_allows(bloc)) _logs.onTransition(bloc, transition);
  }
}
