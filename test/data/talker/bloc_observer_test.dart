import 'package:bloc_effects/bloc_effects.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/infrastructure/talker/bloc_observer/observer.dart';
import 'package:talker_bloc_effects/talker_bloc_effects.dart';

import '../../support.dart';

void main() {
  test('all Bloc callbacks share context and errors are logged once', () async {
    final log = createLog();
    final captured = <Observation>[];
    final previous = CountingObserver();
    final observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter.disabled(),
      effectsSettings: const TalkerBlocEffectsSettings(),
      previous: previous,
      capture: (observation) async {
        log.record(observation);
        captured.add(observation);
      },
    );
    final bloc = CounterBloc();
    observer
      ..onCreate(bloc)
      ..onEvent(bloc, 1)
      ..onChange(bloc, const Change(currentState: 0, nextState: 1))
      ..onTransition(bloc, const Transition(currentState: 0, event: 1, nextState: 1))
      ..onError(bloc, StateError('failed'), StackTrace.empty)
      ..onDone(bloc, 1)
      ..onClose(bloc);
    expect(log.history, hasLength(7));
    expect(captured, hasLength(1));
    expect(previous.calls, 7);
    expect(log.history.every((entry) => entry.message!.contains('foreground(main): ')), isTrue);
    await bloc.close();
  });
  test('exact Bloc filter suppresses ordinary callbacks but not errors', () async {
    final log = createLog();
    final captured = <Observation>[];
    final observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter(
        enabled: true,
        excludedLogs: [],
        excludedHttpUrls: [],
        excludedBlocTypes: ['CounterBloc'],
      ),
      effectsSettings: const TalkerBlocEffectsSettings(),
      previous: CountingObserver(),
      capture: (observation) async {
        log.record(observation);
        captured.add(observation);
      },
    );
    final bloc = CounterBloc();
    observer
      ..onCreate(bloc)
      ..onEvent(bloc, 1)
      ..onChange(bloc, const Change(currentState: 0, nextState: 1))
      ..onTransition(bloc, const Transition(currentState: 0, event: 1, nextState: 1))
      ..onClose(bloc)
      ..onError(bloc, StateError('failed'), StackTrace.empty);
    expect(log.history, hasLength(1));
    expect(captured, hasLength(1));
    await bloc.close();
  });

  test('effects use settings, keep context and forward every emission to the previous observer', () async {
    final log = createLog();
    final previous = CountingEffectsObserver();
    final seen = <Object?>[];
    final original = Bloc.observer;
    Bloc.observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter.disabled(),
      effectsSettings: TalkerBlocEffectsSettings(
        printEffectFullData: false,
        effectFilter: (bloc, effect) {
          seen.add(effect);
          return effect != 'skip';
        },
      ),
      previous: previous,
      capture: (_) async {},
    );
    try {
      final cubit = EffectCubit()
        ..send('saved')
        ..send('saved')
        ..send('skip')
        ..send(null);
      final bloc = EffectBloc()..send('from bloc');
      final effects = log.history.where((entry) => entry.key == BlocEffectLog.logKey).toList();
      expect(effects, hasLength(4));
      expect(effects.every((entry) => entry.message!.startsWith('foreground(main): ')), isTrue);
      expect(effects.first.message, contains('String'));
      expect(effects[2].message, contains('Null'));
      expect(seen, ['saved', 'saved', 'skip', null, 'from bloc']);
      expect(previous.effects, ['saved', 'saved', 'skip', null, 'from bloc']);
      await cubit.close();
      await bloc.close();
    } finally {
      Bloc.observer = original;
    }
  });

  test('exact Bloc filter runs before effect filter and settings can disable effects', () async {
    final log = createLog();
    final original = Bloc.observer;
    Bloc.observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter(
        enabled: true,
        excludedLogs: [],
        excludedHttpUrls: [],
        excludedBlocTypes: ['EffectCubit'],
      ),
      effectsSettings: TalkerBlocEffectsSettings(
        effectFilter: (_, _) => throw StateError('must not run'),
      ),
      previous: CountingObserver(),
      capture: (_) async {},
    );
    try {
      final cubit = EffectCubit()..send(_ThrowingEffect());
      expect(log.history.where((entry) => entry.key == BlocEffectLog.logKey), isEmpty);
      await cubit.close();
    } finally {
      Bloc.observer = original;
    }

    ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter.disabled(),
      effectsSettings: const TalkerBlocEffectsSettings(enabled: false),
      previous: CountingObserver(),
      capture: (_) async {},
    ).onEffect('hidden');
    expect(log.history.where((entry) => entry.key == BlocEffectLog.logKey), isEmpty);
  });

  test('plain effects are logged and formatting failures do not escape', () async {
    final failures = <String>[];
    final log = createLog(reportFailure: failures.add);
    final original = Bloc.observer;
    Bloc.observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter.disabled(),
      effectsSettings: const TalkerBlocEffectsSettings(),
      previous: CountingObserver(),
      capture: (_) async {},
    );
    try {
      final source = PlainEffects()
        ..send('plain')
        ..send(_ThrowingEffect());
      final effects = log.history.where((entry) => entry.key == BlocEffectLog.logKey).toList();
      expect(effects, hasLength(1));
      expect(effects.single.message, contains('Effect emitted'));
      expect(effects.single.message, contains('plain'));
      expect(failures, ['Bloc effect logging failed']);
      await source.close();

      final filteringObserver = ObservatoryBlocObserver(
        log: log,
        filter: const ObservationFilter.disabled(),
        effectsSettings: TalkerBlocEffectsSettings(
          effectFilter: (_, _) => throw StateError('filter'),
        ),
        previous: CountingObserver(),
        capture: (_) async {},
      );
      expect(() => filteringObserver.onEffect('filtered'), returnsNormally);
      expect(failures, ['Bloc effect logging failed', 'Bloc effect logging failed']);
    } finally {
      Bloc.observer = original;
    }
  });
}

final class CounterBloc extends Bloc<int, int> {
  CounterBloc() : super(0);
}

final class CountingObserver extends BlocObserver {
  int calls = 0;
  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    calls++;
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    calls++;
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    calls++;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    calls++;
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    calls++;
  }

  @override
  void onDone(Bloc<dynamic, dynamic> bloc, Object? event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(bloc, event, error, stackTrace);
    calls++;
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    calls++;
  }
}

final class CountingEffectsObserver extends BlocWithEffectsObserver {
  final List<Object?> effects = [];

  @override
  void onEffect<E>(E effect) {
    super.onEffect(effect);
    effects.add(effect);
  }
}

final class EffectCubit extends CubitWithEffects<int, Object?> {
  EffectCubit() : super(0);

  void send(Object? effect) => emitEffect(effect);
}

final class EffectBloc extends BlocWithEffects<int, int, Object?> {
  EffectBloc() : super(0);

  void send(Object? effect) => emitEffect(effect);
}

final class PlainEffects extends _Closable with Effects<Object?> {
  void send(Object? effect) => emitEffect(effect);
}

class _Closable implements Closable {
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;
}

final class _ThrowingEffect {
  @override
  String toString() => throw StateError('format');
}
