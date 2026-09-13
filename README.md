# observatory

![Observatory routes connected log sources through a shared Talker with thread and zone context.](assets/hero.png)

Isolate-aware Flutter logs, bounded history, safe HTTP logging and Sentry incident capture.
Every connected source uses the same `thread(zoneName): message` format in console output,
the log screen, exported text and breadcrumbs. Multiline entries prefix every line.

## Start an isolate

```yaml
dependencies:
  observatory: ^2.0.0
```

```dart
Future<void> main() => Observatory.run<void>(
  config: const Config(),
  thread: ObservatoryThread.foreground,
  zoneName: 'main',
  body: () {
    final dio = Dio();
    Observatory.attachTo(dio);
    runApp(
      ObservatoryWidget(
        child: MaterialApp(
          navigatorObservers: Observatory.navigatorObservers,
          home: const HomePage(),
        ),
      ),
    );
  },
);
```

Observatory creates the Flutter binding and runs `body` in the same zone. Call it before
creating a binding yourself. `isStarted` means local logging is ready; `isSentryEnabled`
reports whether remote capture initialized successfully. Failed Sentry initialization
leaves local logging available and still runs the application.

The result of `body` becomes the result of `run`. An exception in `body` is captured and
returned with its original stack. The runtime stays active after `body` returns, including
a `runApp` call. A second or concurrent `run` in the same isolate fails with `StateError`.

## Log sources and zones

![Foreground and background isolates start separately, while nested zones preserve their thread.](assets/safety.png)

```dart
Observatory.record(LogLevel.info, 'Session restored');
Observatory.talker.info('Direct Talker call');
print('Console message');
debugPrint('Flutter diagnostic');

await Observatory.runInZone('profile', () async {
  await loadProfile();
  Observatory.record(LogLevel.info, 'Profile loaded');
});
```

`print` and `debugPrint` become `info` records, with console output, history and eligibility
for breadcrumbs. They do not create incidents. Context is captured when a log is received,
including across asynchronous continuations. Their own console output is not recaptured.
Zone names are trimmed, empty names become `unspecified`, and names are limited to 20 characters.
Direct calls to the managed Talker outside the runtime zone use the isolate's startup context.

Pass **`Observatory.talker`** to third-party Talker integrations. Standard methods, `handle`
and `logCustom` use the common preparation path. Observatory owns the logger, history and
error preparation; replacing those with `talker.configure` is unsupported. Observers can still be configured; use `Config.filter` for filtering. Console output can be disabled with
`talker.configure(settings: TalkerSettings(useConsoleLogs: false))`.

Each background isolate needs its own entry point:

```dart
Future<void> worker() => Observatory.run<void>(
  config: const Config(),
  thread: ObservatoryThread.background,
  zoneName: 'downloads',
  body: () async {
    print('Worker ready');
    await downloadFiles();
  },
);
```

`print` interception covers the runtime zone and its descendants. Logs before startup,
other Talker instances, direct `stdout`, arbitrary `dart:developer.log` calls and native
platform logs are outside that interception.

## Incidents and Sentry

![record filters local logs; capture records an incident locally and attempts Sentry capture when enabled.](assets/flow.png)

```dart
try {
  await syncProfile();
} on Object catch (error, stack) {
  await Observatory.capture(
    LogLevel.error,
    'Profile sync failed',
    error: error,
    stackTrace: stack,
  );
}

await Observatory.capture(LogLevel.warning, 'Profile is incomplete');
```

`record` writes an ordinary log. `capture` writes one local incident and submits a Sentry
event when remote capture is enabled. An `error` is optional. Messages, timestamps, levels,
isolate context and exception chains are retained. Derived error locations are added as
context without replacing exception types, values or the transaction name.

Configure `Config.sentry` with `SentrySpec`; the complete example is in
[`example/observatory_example.dart`](example/observatory_example.dart). Sentry is disabled by
default. Observatory owns its Sentry initialization; do not initialize a second Sentry
runtime in the same isolate. SDK screenshot masking defaults remain enabled.

Dedupe uses error identity, location and operation message within `dedupeTtl`, bounded by
`dedupeMaxEntries`. Message-only events also include isolate context. SDK object-identity
deduplication is disabled. An SDK call completing does not guarantee server acceptance.

```dart
await Observatory.bindUser(id: user.id, email: user.email);
await Observatory.bindDevice(connectedDeviceId: device.id, platformDeviceId: platformId);
await Observatory.clearUser();
await Observatory.clearDevice();
```

## Privacy, filters and limits

`Config.redaction` controls the common `RedactionPolicy`. Sensitive headers, query parameters,
URI credentials, JSON and FormData fields are masked before storage. The same policy cleans
Sentry requests, breadcrumbs, contexts, extra data and spans. Original HTTP objects remain
unchanged. Recognizable key/value text is scrubbed; arbitrary free text cannot be guaranteed
free of unknown secrets. `RedactionPolicy.disabled()` is an explicit opt-out from masking.

`HttpLogSpec()` omits headers and bodies; `HttpLogSpec.detailed()` includes sanitized values.
`attachTo` is idempotent for each Dio. Bloc errors are captured once; other Bloc callbacks
and navigation use the common history.

`ObservationFilter` filters ordinary records by message substring, HTTP URL regular expression
and exact Bloc type name. It does not suppress explicit or uncaught incidents. Bloc name
filters must account for obfuscation in the host application.

- `Config.historyLimit`: 1000 records by default; zero disables retention, negative is invalid.
- Formatting: maximum depth 8, 1000 visited elements, 16,384 characters per rendered record.
  Cycles and truncation have explicit markers. These bounds also apply when masking is disabled.
- Breadcrumbs: filter by `logsLevel`, then take `logsMaxBreadcrumbs`; combined SDK and history
  breadcrumbs are capped by `maxBreadcrumbs`. Collection reads do not expose mutable payloads.
- Logging failures use a guarded console fallback and do not block HTTP processing or a
  separate attempt to capture the incident remotely.

## Log screen and shutdown

```dart
Navigator.of(context).push(MaterialPageRoute<void>(
  builder: (_) => const ObservatoryLogScreen(appBarTitle: 'Logs'),
));

await Observatory.close();
```

`close` waits for pending capture operations, closes the owned Sentry runtime, detaches Dio
wrappers, clears history and restores previous Flutter/platform/debugPrint/Bloc handlers.
Handlers replaced by the host after startup are preserved. The host still owns its Dio
clients. Close the runtime when an isolate's work is complete or during test cleanup;
a later `run` can initialize it again.

## Migrate from 1.x

1. Replace `initPackage`, `Observatory.start` and `Observatory.runZoned` with `Observatory.run`.
2. Remove `Dependencies(talker: ...)` and obtain the shared instance from `Observatory.talker`.
3. Move `HttpLogSpec.redaction` to `Config.redaction`.
4. Replace `disabledBlocLogs` with exact names in `ObservationFilter.excludedBlocTypes`.
5. Use `ObservatoryLogScreen` and `ObservatoryWidget` instead of facade widget builders.
6. Replace test resets with `await Observatory.close()`; initialize every background isolate.

## Development

```sh
make get
make analyze
make format-check
make test
make publish-dry-run
```

CI uses Flutter 3.47.2 and runs these checks on pushes and pull requests. Sentry tests use a
local transport; they do not contact a Sentry server or establish physical-device behavior.

License: MIT.
