import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/data/talker/bloc_observer/observer.dart';

import '../../support.dart';

void main() {
  test('all Bloc callbacks share context and errors are logged once', () async {
    final log = createLog();
    final captured = <Observation>[];
    final previous = CountingObserver();
    final observer = ObservatoryBlocObserver(
      log: log,
      filter: const ObservationFilter.disabled(),
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
