import 'dart:async';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/application/runtime.dart';
import 'package:talker/talker.dart' hide LogLevel;

import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Observatory.close);

  test('print, debugPrint, direct Talker and nested async zones share history without recursion', () async {
    final console = <String>[];
    await runZoned(
      () => Observatory.run<void>(
        config: const Config(),
        zoneName: ' main ',
        body: () async {
          expect(Observatory.isStarted, isTrue);
          expect(LaunchMode.current, LaunchModeType.foreground);
          // ignore: avoid_print
          print('printed\nsecond line');
          debugPrint('debug printed');
          Observatory.talker.info('direct');
          Observatory.record(LogLevel.warning, 'recorded');
          await Observatory.runInZone('worker', () async {
            await Future<void>.delayed(Duration.zero);
            debugPrint('nested debug');
            // ignore: avoid_print
            print('nested print');
          });
          await Future<void>.delayed(Duration.zero);
        },
      ),
      zoneSpecification: ZoneSpecification(print: (_, _, _, message) => console.add(message)),
    );
    expect(Observatory.talker.history, hasLength(6));
    expect(console, hasLength(6));
    expect(console[0], 'foreground(main): printed\nforeground(main): second line');
    expect(console[4], 'foreground(worker): nested debug');
    expect(console[5], 'foreground(worker): nested print');
    Observatory.talker.info('outside child zone');
    expect(console.last, 'foreground(main): outside child zone');
  });

  test('queued debug messages retain origin across zones and every wrapped line has context', () async {
    await Observatory.run<void>(
      config: const Config(),
      zoneName: 'main',
      body: () async {
        Observatory.talker.configure(settings: TalkerSettings(useConsoleLogs: false));
        Observatory.runInZone('first', () => debugPrint('x' * 13000));
        Observatory.runInZone('second', () => debugPrint('several words wrap here', wrapWidth: 8));
        await debugPrintDone;
      },
    );
    expect(Observatory.talker.history, hasLength(2));
    expect(Observatory.talker.history[0].message, startsWith('foreground(first): '));
    expect(
      Observatory.talker.history[1]
          .generateTextMessage()
          .split('\n')
          .every((line) => line.startsWith('foreground(second): ')),
      isTrue,
    );
  });

  test('background scope changes launch mode without changing neighboring foreground work', () async {
    await Observatory.run<void>(
      config: const Config(),
      zoneName: 'main',
      body: () async {
        Observatory.talker.configure(settings: TalkerSettings(useConsoleLogs: false));
        await LaunchMode.withBackgroundMode(
          () => Observatory.runInZone('push', () async {
            await Future<void>.delayed(Duration.zero);
            Observatory.talker.info('background task');
          }),
        );
        Observatory.talker.info('foreground task');
      },
    );
    expect(Observatory.talker.history.map((entry) => entry.message), [
      'background(push): background task',
      'foreground(main): foreground task',
    ]);
  });

  test('concurrent and repeated runs reject; close allows another run', () async {
    final release = Completer<void>();
    final first = Observatory.run<int>(
      config: const Config(),
      zoneName: 'main',
      body: () async {
        await release.future;
        return 42;
      },
    );
    await expectLater(Observatory.run<void>(config: const Config(), zoneName: 'other', body: () {}), throwsStateError);
    release.complete();
    expect(await first, 42);
    await Observatory.close();
    expect(Observatory.isStarted, isFalse);
    expect(await Observatory.run<int>(config: const Config(), zoneName: 'again', body: () => 7), 7);
  });

  test('a new run refreshes package context with the next config and clock', () async {
    final firstClock = MutableClock()..value = DateTime.utc(2026, 9, 14, 1);
    await Observatory.run<void>(
      config: const Config(historyLimit: 1),
      zoneName: 'first',
      clock: firstClock,
      body: () {
        Observatory.talker
          ..info('discarded')
          ..info('retained');
      },
    );
    expect(Observatory.talker.history, hasLength(1));
    expect(Observatory.talker.history.single.time, firstClock.value);
    await Observatory.close();

    final secondClock = MutableClock()..value = DateTime.utc(2026, 9, 14, 2);
    await Observatory.run<void>(
      config: const Config(historyLimit: 2),
      zoneName: 'second',
      clock: secondClock,
      body: () {
        Observatory.talker
          ..info('first')
          ..info('second');
      },
    );
    expect(Observatory.talker.history, hasLength(2));
    expect(Observatory.talker.history.last.time, secondClock.value);
  });

  test('body errors return the original object and stack without hanging', () async {
    final error = StateError('body');
    final stack = StackTrace.fromString('original stack');
    final future = Observatory.run<void>(
      config: const Config(),
      zoneName: 'main',
      body: () async {
        await Future<void>.delayed(Duration.zero);
        Error.throwWithStackTrace(error, stack);
      },
    );
    try {
      await future.timeout(const Duration(seconds: 2));
      fail('Expected body error');
    } on Object catch (actual, actualStack) {
      expect(identical(actual, error), isTrue);
      expect(actualStack.toString(), contains('original stack'));
    }
    expect(
      Observatory.talker.history.where((entry) => entry.message!.contains('Observatory body failed')),
      hasLength(1),
    );
  });

  test('close restores hooks, preserves later replacements and detaches Dio once', () async {
    final beforePrint = debugPrint;
    final beforeFlutter = FlutterError.onError;
    final beforePlatform = PlatformDispatcher.instance.onError;
    final beforeBloc = Bloc.observer;
    final dio = Dio();
    final originalAdapter = dio.httpClientAdapter;
    await Observatory.run<void>(
      config: const Config(),
      zoneName: 'main',
      body: () {
        Observatory.attachTo(dio);
        final count = dio.interceptors.length;
        Observatory.attachTo(dio);
        expect(dio.interceptors, hasLength(count));
        expect(identical(Observatory.navigatorObservers, Observatory.navigatorObservers), isTrue);
      },
    );
    await Observatory.close();
    expect(identical(debugPrint, beforePrint), isTrue);
    expect(identical(FlutterError.onError, beforeFlutter), isTrue);
    expect(identical(PlatformDispatcher.instance.onError, beforePlatform), isTrue);
    expect(identical(Bloc.observer, beforeBloc), isTrue);
    expect(identical(dio.httpClientAdapter, originalAdapter), isTrue);
    expect(dio.interceptors, hasLength(1));
    await Observatory.run<void>(config: const Config(), zoneName: 'main', body: () {});
    void replacement(String? message, {int? wrapWidth}) {}
    debugPrint = replacement;
    await Observatory.close();
    expect(identical(debugPrint, replacement), isTrue);
    debugPrint = beforePrint;
    dio.close();
  });

  test('Sentry startup failure preserves local logs and executes body', () async {
    var called = false;
    final runtime = ObservatoryRuntime(
      config: Config(sentry: sentrySpec()),
      isolate: const IsolateContext(launchMode: LaunchModeType.foreground, zoneName: 'main'),
      clock: MutableClock(),
      initializeSentry: (_, {required launchMode}) async {
        expect(launchMode, LaunchModeType.foreground);
        throw StateError('startup');
      },
    );
    try {
      await runtime.run<void>(() {
        called = true;
        runtime.talker.info('still working');
      });
      expect(called, isTrue);
      expect(runtime.started, isTrue);
      expect(runtime.sentryActive, isFalse);
      expect(runtime.talker.history.any((entry) => entry.message!.contains('still working')), isTrue);
    } finally {
      await runtime.close();
    }
  });

  test('SDK hooks send once, local failures stay isolated and original hooks return', () async {
    final originalFlutter = FlutterError.onError;
    final originalPlatform = PlatformDispatcher.instance.onError;
    var flutterCalls = 0;
    var platformCalls = 0;
    FlutterError.onError = (_) {
      flutterCalls++;
    };
    PlatformDispatcher.instance.onError = (_, _) {
      platformCalls++;
      return true;
    };
    final hostFlutter = FlutterError.onError;
    final hostPlatform = PlatformDispatcher.instance.onError;
    final transport = RecordingTransport();
    final runtime = ObservatoryRuntime(
      config: Config(sentry: sentrySpec(attachLogs: false)),
      isolate: const IsolateContext(launchMode: LaunchModeType.foreground, zoneName: 'main'),
      clock: MutableClock(),
      initializeSentry: (sink, {required launchMode}) => initializeTestSentry(sink, transport, flutterHooks: true),
    );
    try {
      await runtime.run<void>(() async {
        runtime.talker.configure(observer: FailingObserver(), settings: TalkerSettings(useConsoleLogs: false));
        runtime.runInZone('hooks', () {
          FlutterError.onError!(
            FlutterErrorDetails(
              exception: StateError('flutter failure'),
              stack: StackTrace.fromString('#0 render (package:mobile/view.dart:1:1)'),
            ),
          );
          expect(
            PlatformDispatcher.instance.onError!(
              StateError('platform failure'),
              StackTrace.fromString('#0 dispatch (package:mobile/dispatch.dart:2:1)'),
            ),
            isTrue,
          );
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          transport.events,
          hasLength(2),
          reason: 'remote=${runtime.sentryActive}, flutter=$flutterCalls, platform=$platformCalls',
        );
        await runtime.capture(
          runtime.talker.observation(LogLevel.error, 'explicit operation', error: StateError('explicit')),
        );
      });
      expect(transport.events, hasLength(3));
      expect(runtime.talker.history, hasLength(3));
      expect(flutterCalls, 1);
      expect(platformCalls, 1);
      expect(transport.events.take(2).every((event) => (event['tags'] as Map)['zoneName'] == 'hooks'), isTrue);
      await runtime.close();
      expect(identical(FlutterError.onError, hostFlutter), isTrue);
      expect(identical(PlatformDispatcher.instance.onError, hostPlatform), isTrue);
    } finally {
      await runtime.close();
      FlutterError.onError = originalFlutter;
      PlatformDispatcher.instance.onError = originalPlatform;
    }
  });

  test('close during initialization settles run and restores debugPrint', () async {
    final initialize = Completer<void>();
    final beforePrint = debugPrint;
    var bodyCalled = false;
    final runtime = ObservatoryRuntime(
      config: Config(sentry: sentrySpec()),
      isolate: const IsolateContext(launchMode: LaunchModeType.foreground, zoneName: 'main'),
      clock: MutableClock(),
      initializeSentry: (_, {required launchMode}) => initialize.future,
    );
    final run = runtime.run<void>(() {
      bodyCalled = true;
    });
    final rejected = expectLater(run, throwsStateError);
    final closed = runtime.close();
    initialize.complete();
    await rejected;
    await closed;
    expect(bodyCalled, isFalse);
    expect(runtime.started, isFalse);
    expect(identical(debugPrint, beforePrint), isTrue);
  });

  test('invalid limits fail before installing hooks', () {
    final original = debugPrint;
    expect(
      () => Observatory.run<void>(config: const Config(historyLimit: -1), zoneName: 'main', body: () {}),
      throwsArgumentError,
    );
    expect(
      () => Observatory.run<void>(
        config: Config(sentry: sentrySpec(logsLimit: -1)),
        zoneName: 'main',
        body: () {},
      ),
      throwsArgumentError,
    );
    expect(Observatory.isStarted, isFalse);
    expect(identical(debugPrint, original), isTrue);
  });

  test('unawaited zone errors are captured once with the originating context', () async {
    await Observatory.run<void>(
      config: const Config(),
      zoneName: 'main',
      body: () async {
        Observatory.runInZone('timer', () {
          Timer.run(() => throw StateError('uncaught'));
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    final records = Observatory.talker.history
        .where((entry) => entry.message!.contains('Unhandled zone error'))
        .toList();
    expect(records, hasLength(1));
    expect(records.single.message, startsWith('foreground(timer): '));
  });

  test('separate background isolate initializes and preserves its own context', () async {
    final messages = await Isolate.run(_background).timeout(const Duration(seconds: 5));
    expect(messages, hasLength(2));
    expect(messages[0], 'background(downloads): background print');
    expect(messages[1], 'background(downloads): background talker');
    expect(Observatory.isStarted, isFalse);
  });

  test('separate computational isolate detects isolate mode automatically', () async {
    final messages = await Isolate.run(_worker).timeout(const Duration(seconds: 5));
    expect(messages, ['isolate(worker): worker log']);
    expect(Observatory.isStarted, isFalse);
  });

  testWidgets('widgets and navigation use the shared Talker', (tester) async {
    await Observatory.run<void>(config: const Config(), zoneName: 'main', body: () {});
    await tester.pumpWidget(
      ObservatoryWidget(
        child: MaterialApp(
          navigatorObservers: Observatory.navigatorObservers,
          home: const ObservatoryLogScreen(appBarTitle: 'Logs'),
        ),
      ),
    );
    expect(find.text('Logs'), findsOneWidget);
    expect(Observatory.talker.history.any((entry) => entry.key == TalkerKey.route), isTrue);
    expect(Observatory.talker.history.every((entry) => entry.message!.contains('foreground(main): ')), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await Observatory.close();
  });
}

Future<List<String?>> _worker() async {
  await Observatory.run<void>(
    config: const Config(),
    zoneName: 'worker',
    body: () => Observatory.talker.info('worker log'),
  );
  final messages = Observatory.talker.history.map((entry) => entry.message).toList();
  await Observatory.close();
  return messages;
}

Future<List<String?>> _background() async {
  return LaunchMode.withBackgroundMode(() async {
    await Observatory.run<void>(
      config: const Config(),
      zoneName: 'downloads',
      body: () {
        // ignore: avoid_print
        print('background print');
        Observatory.talker.info('background talker');
      },
    );
    final messages = Observatory.talker.history.map((entry) => entry.message).toList();
    await Observatory.close();
    return messages;
  });
}

final class FailingObserver extends TalkerObserver {
  @override
  void onLog(TalkerData log) => throw StateError('logger');
}
