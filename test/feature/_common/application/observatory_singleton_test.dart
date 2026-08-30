import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/core/package_context.dart';
import 'package:talker/talker.dart' hide LogLevel;

void main() {
  setUp(() {
    Observatory.reset();
    packageContext.reset();
  });

  tearDown(() {
    Observatory.reset();
    packageContext.reset();
  });

  test('static record and capture write through Talker', () async {
    final talker = Talker(
      settings: TalkerSettings(
        useConsoleLogs: false,
      ),
    );

    await initPackage(
      config: const Config(),
      dependencies: Dependencies(
        talker: talker,
      ),
    );
    Observatory.start(
      thread: ObservatoryThread.foreground,
      zoneName: 'main',
    );

    Observatory.record(LogLevel.info, 'ready');
    await Observatory.capture(LogLevel.error, 'sync failed');

    expect(talker.history, isNotEmpty);
  });

  test('second start in the same isolate throws', () async {
    await initPackage(
      config: const Config(),
      dependencies: const Dependencies(),
    );
    Observatory.start(
      thread: ObservatoryThread.foreground,
      zoneName: 'main',
    );

    expect(
      () => Observatory.start(
        thread: ObservatoryThread.foreground,
        zoneName: 'main',
      ),
      throwsStateError,
    );
  });

  test('static API throws before start', () {
    expect(
      () => Observatory.record(LogLevel.info, 'too early'),
      throwsStateError,
    );
  });
}
