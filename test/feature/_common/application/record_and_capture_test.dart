import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/src/feature/_common/application/capture_incident.dart';
import 'package:observatory/src/feature/_common/application/record_observation.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';

void main() {
  group('RecordObservation', () {
    test('writes to the log port', () {
      final log = _MemoryLog();
      RecordObservation(
        log: log,
        filter: const ObservationFilter.disabled(),
      ).call(_observation());
      expect(log.items, hasLength(1));
      expect(log.items.single.message, 'ready');
    });

    test('drops messages excluded by the filter', () {
      final log = _MemoryLog();
      RecordObservation(
        log: log,
        filter: const ObservationFilter(
          enabled: true,
          excludedLogs: ['secret'],
          excludedHttpUrls: [],
          excludedBlocTypes: [],
        ),
      ).call(_observation(message: 'secret token'));
      expect(log.items, isEmpty);
    });
  });

  group('CaptureIncident', () {
    test('writes to log and sink', () async {
      final log = _MemoryLog();
      final sink = _MemorySink();
      await CaptureIncident(log: log, sink: sink).call(_observation(level: LogLevel.error));
      expect(log.items, hasLength(1));
      expect(sink.items, hasLength(1));
    });
  });
}

Observation _observation({
  String message = 'ready',
  LogLevel level = LogLevel.info,
}) {
  return Observation(
    message: message,
    level: level,
    isolate: const IsolateContext.unspecified(),
    time: DateTime.utc(2026),
  );
}

final class _MemoryLog implements ObservationLog {
  final List<Observation> items = [];

  @override
  void record(Observation observation) {
    items.add(observation);
  }
}

final class _MemorySink implements IncidentSink {
  final List<Observation> items = [];

  @override
  Future<void> capture(Observation observation) async {
    items.add(observation);
  }

  @override
  Future<void> bindUser({
    String? id,
    String? email,
  }) async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> bindDevice({
    String? connectedDeviceId,
    String? platformDeviceId,
  }) async {}

  @override
  Future<void> clearDevice() async {}
}
