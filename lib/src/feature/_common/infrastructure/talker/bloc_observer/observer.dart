import 'dart:async';

import 'package:bloc_effects/bloc_effects.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:observatory/src/feature/_common/infrastructure/talker/managed_talker.dart';
import 'package:talker_bloc_effects/talker_bloc_effects.dart';

final class ObservatoryBlocObserver extends BlocObserver implements BlocWithEffectsObserver {
  final ManagedTalker log;
  final ObservationFilter filter;
  final Future<void> Function(Observation) capture;
  final BlocObserver previous;
  final TalkerBlocEffectsObserver _logs;

  ObservatoryBlocObserver({
    required this.log,
    required this.filter,
    required TalkerBlocEffectsSettings effectsSettings,
    required this.capture,
    required this.previous,
  }) : _logs = TalkerBlocEffectsObserver(
         talker: log,
         settings: const TalkerBlocLoggerSettings(printChanges: true, printCreations: true, printClosings: true),
         effectsSettings: TalkerBlocEffectsSettings(
           enabled: effectsSettings.enabled,
           printEffectFullData: effectsSettings.printEffectFullData,
           effectFilter: (bloc, effect) {
             if (bloc != null && !_allowsBloc(filter, bloc)) return false;
             return effectsSettings.effectFilter?.call(bloc, effect) ?? true;
           },
         ),
       );

  bool _allows(BlocBase<dynamic> bloc) => _allowsBloc(filter, bloc);

  @override
  void onBlocEffect(BlocBase<dynamic> bloc, Object? effect) {
    try {
      // ignore: invalid_use_of_protected_member
      _logs.onBlocEffect(bloc, effect);
    } on Object {
      log.reportFailure('Bloc effect logging failed');
    }
    final previous = this.previous;
    if (previous is BlocWithEffectsObserver) {
      // ignore: invalid_use_of_protected_member
      previous.onBlocEffect(bloc, effect);
    }
  }

  @override
  void onEffect<E>(E effect) {
    try {
      // ignore: invalid_use_of_protected_member
      _logs.onEffect(effect);
    } on Object {
      log.reportFailure('Bloc effect logging failed');
    }
    final previous = this.previous;
    if (previous is BlocWithEffectsObserver) {
      // ignore: invalid_use_of_protected_member
      previous.onEffect<E>(effect);
    }
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

bool _allowsBloc(ObservationFilter filter, BlocBase<dynamic> bloc) {
  // Matching by name is the public filter contract; obfuscated names need host-specific filters.
  // ignore: avoid_type_to_string, no_runtimeType_toString
  return filter.allowsBlocType(bloc.runtimeType.toString());
}
