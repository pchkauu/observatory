import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:observatory/observatory.dart';
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

Future<void> main() async {
  final talker = TalkerFlutter.init();

  await initPackage(
    config: Config(
      filter: ObservationFilter(
        enabled: true,
        excludedLogs: const [
          'password',
          'Authorization',
        ],
        excludedHttpUrls: [
          RegExp(r'/health$'),
        ],
        excludedBlocTypes: const [
          'HydratedBloc',
        ],
      ),
      httpLog: const HttpLogSpec.detailed(),
      disabledBlocLogs: const [
        'HydratedBloc',
      ],
      sentry: SentrySpec(
        enabled: const String.fromEnvironment('SENTRY_DSN').isNotEmpty,
        appPackageName: 'observatory_example',
        dsn: const String.fromEnvironment('SENTRY_DSN'),
        environment: kReleaseMode ? 'production' : 'development',
        release: 'observatory_example@0.1.0+1',
        dist: '1',
        sampleRate: 1,
        attachScreenshot: true,
        attachLogs: true,
        logsMaxBreadcrumbs: 50,
        logsLevel: LogLevel.warning,
        maxBreadcrumbs: 100,
        dedupeTtl: const Duration(minutes: 2),
        dedupeMaxEntries: 200,
        anrEnabled: true,
        anrTimeoutInterval: const Duration(seconds: 5),
        enableAppHangTracking: true,
        appHangTimeoutInterval: const Duration(seconds: 2),
      ),
    ),
    dependencies: Dependencies(
      talker: talker,
    ),
  );

  Observatory.start(
    thread: ObservatoryThread.foreground,
    zoneName: 'main',
  );

  return Observatory.runZoned(() async {
    await Observatory.bindUser(id: 'user-42', email: 'qa@example.com');
    await Observatory.bindDevice(
      connectedDeviceId: 'device-7',
      platformDeviceId: 'pixel-8',
    );

    final dio = Dio(
      BaseOptions(baseUrl: 'https://api.example.com'),
    );
    Observatory.attachTo(dio);

    runApp(ExampleApp(dio: dio));
  });
}

class ExampleApp extends StatelessWidget {
  final Dio dio;

  const ExampleApp({
    required this.dio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ObservatoryWidget(
      child: MaterialApp(
        navigatorObservers: Observatory.navigatorObservers,
        home: ExampleHome(
          dio: dio,
        ),
      ),
    );
  }
}

class ExampleHome extends StatelessWidget {
  final Dio dio;

  const ExampleHome({
    required this.dio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Observatory example'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ObservatoryLogScreen(
                    appBarTitle: 'Logs',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: () {
              Observatory.record(LogLevel.info, 'Home opened');
            },
            child: const Text('Record info'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _syncProfile,
            child: const Text('Catch and capture'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _pingBackend,
            child: const Text('HTTP with capture'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncProfile() async {
    try {
      throw const FormatException('invalid profile payload');
    } on Object catch (error, stackTrace) {
      await Observatory.capture(
        LogLevel.error,
        'Profile sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pingBackend() async {
    try {
      await dio.get<void>('/v1/profile');
    } on Object catch (error, stackTrace) {
      await Observatory.capture(
        LogLevel.error,
        'Profile request failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
