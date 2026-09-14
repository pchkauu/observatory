import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/infrastructure/log_sanitizer.dart';
import 'package:talker/talker.dart' as talker;

import '../../support.dart';

void main() {
  test('all public Talker entry points preserve context, levels and one record', () {
    final output = <String>[];
    final log = createLog(output: output.add)
      ..verbose('verbose')
      ..debug('debug')
      ..info('info')
      ..warning('warning')
      ..error('error')
      ..critical('critical')
      ..log('generic')
      ..handle(StateError('broken'), StackTrace.fromString('stack\nline'), 'operation')
      ..logCustom(_CustomLog());
    expect(log.history, hasLength(9));
    expect(output, hasLength(9));
    expect(log.last(limit: 9).take(6).map((entry) => entry.level), LogLevel.values);
    for (final entry in log.history) {
      expect(entry.generateTextMessage().split('\n').every((line) => line.startsWith('foreground(main): ')), isTrue);
    }
    expect(log.history.last.key, 'custom');
    expect(log.history.last.generateTextMessage(), contains('custom rendering'));
  });

  test('history evicts, handles zero, rejects negative and detaches errors', () {
    final log = createLog(limit: 2)
      ..info('first')
      ..info('second');
    final error = _MutableError();
    log.error('third', error);
    error.text = 'changed';
    expect(log.history, hasLength(2));
    expect(log.history.first.message, contains('second'));
    expect(log.history.last.message, contains('original'));
    expect(log.history.last.message, isNot(contains('changed')));
    expect(log.last(limit: 2).last.error, isNull);
    expect(log.last(limit: 0), isEmpty);
    expect(() => log.last(limit: -1), throwsArgumentError);
    expect(() => createLog(limit: -1), throwsArgumentError);
    final empty = createLog(limit: 0)..info('not retained');
    expect(empty.history, isEmpty);
    log.cleanHistory();
    expect(log.history, isEmpty);
  });

  test('filters ordinary messages once but preserves incidents', () {
    final log = createLog(
      filter: const ObservationFilter(
        enabled: true,
        excludedLogs: ['skip'],
        excludedHttpUrls: [],
        excludedBlocTypes: [],
      ),
    );
    final incident = log.observation(LogLevel.error, 'skip incident');
    log
      ..info('skip normal')
      ..record(incident);
    expect(log.history, hasLength(1));
    expect(log.history.single.message, contains('skip incident'));
  });

  test('stream closes and multiline truncation retains every complete prefix', () async {
    final log = createLog();
    final done = Completer<void>();
    final received = <talker.TalkerData>[];
    final subscription = log.stream.listen(received.add, onDone: done.complete);
    log.info('\n' * 2000);
    final record = log.last(limit: 1).single;
    expect(record.prefixedMessage.length, lessThanOrEqualTo(LogSanitizer.maxLength));
    expect(record.prefixedMessage.split('\n').every((line) => line.startsWith('foreground(main): ')), isTrue);
    expect(record.message, contains('<truncated>'));
    await log.close();
    await done.future;
    expect(received, hasLength(1));
    expect(log.history, isEmpty);
    await subscription.cancel();
  });

  test('formatting, observer and console failures do not escape or prevent retention', () {
    final failures = <String>[];
    final log = createLog(output: (_) => throw StateError('output'), reportFailure: failures.add)
      ..configure(observer: _ThrowingObserver());
    expect(() => log.error('operation', _ThrowingError()), returnsNormally);
    expect(log.history, hasLength(1));
    expect(failures, containsAll(['Log formatting failed', 'Talker output failed', 'Console output failed']));
    log.info('x' * 20000);
    expect(log.history.last.message!.length, lessThanOrEqualTo(LogSanitizer.maxLength));
  });
}

final class _CustomLog extends talker.TalkerLog {
  _CustomLog() : super('raw', key: 'custom');
  @override
  String generateTextMessage({talker.TimeFormat timeFormat = talker.TimeFormat.timeAndSeconds}) =>
      'custom rendering\nsecond';
}

final class _MutableError {
  String text = 'original';
  @override
  String toString() => text;
}

final class _ThrowingError {
  @override
  String toString() => throw StateError('format');
}

final class _ThrowingObserver extends talker.TalkerObserver {
  @override
  void onLog(talker.TalkerData log) => throw StateError('observer');
}
