import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';
import 'package:observatory/src/feature/_common/infrastructure/error_classifier.dart';
import 'package:observatory/src/feature/_common/infrastructure/log_sanitizer.dart';
import 'package:talker/talker.dart' as talker;

/// All public Talker entry points reach the same preparation and history path.
final class ManagedTalker extends talker.Talker implements ObservationLog, ObservationHistory {
  final ObservationClock clock;
  final IsolateContext Function() context;
  final LogSanitizer sanitizer;
  final ObservationFilter observationFilter;
  final int historyLimit;
  final void Function(String) output;
  final void Function(String) reportFailure;
  final Queue<_ObservationLog> _records = ListQueue();
  final StreamController<talker.TalkerData> _events = StreamController.broadcast();
  talker.TalkerObserver? _observer;
  bool _closed = false;
  bool _consoleEnabled = true;

  ManagedTalker({
    required this.clock,
    required this.context,
    required this.sanitizer,
    required this.observationFilter,
    required this.historyLimit,
    required this.output,
    required this.reportFailure,
  }) : super(settings: talker.TalkerSettings(useConsoleLogs: false, useHistory: false)) {
    if (historyLimit < 0) throw ArgumentError.value(historyLimit, 'historyLimit');
  }

  Observation observation(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) => Observation(
    message: message,
    level: level,
    isolate: context(),
    time: clock.now(),
    error: error,
    stackTrace: stackTrace,
  );

  @override
  void record(Observation observation) => write(observation, incident: true);

  void write(Observation observation, {bool incident = false, String? key, String? title, talker.AnsiPen? pen}) {
    if (_closed || (!settings.enabled && !incident)) return;
    if (!incident && !observationFilter.allowsLog(observation.message)) return;
    var message = observation.message;
    try {
      const classifier = FrameworkErrorClassifier();
      message = ErrorIdentity.formatLogMessage(
        message,
        describedType: classifier.describe(observation.error),
        typeIdentifier: classifier.typeIdentifier(observation.error),
      );
      if (observation.error != null) message += '\n${observation.error}';
      if (observation.stackTrace != null) message += '\n${observation.stackTrace}';
      message = sanitizer.text(message);
    } on Object {
      message = '${sanitizer.text(observation.message)}\n<unavailable error details>';
      reportFailure('Log formatting failed');
    }
    final prepared = Observation(
      message: sanitizer.boundedMessage(message, prefixLength: observation.isolate.prefix.length + 2),
      level: observation.level,
      isolate: observation.isolate,
      time: observation.time,
    );
    final data = _ObservationLog(prepared, sanitizer, key: key, title: title, pen: pen);
    if (historyLimit > 0) {
      if (_records.length == historyLimit) _records.removeFirst();
      _records.addLast(data);
    }
    if (key != null) {
      data.title = settings.getTitleByKey(key);
      data.pen = settings.getPenByKey(key, fallbackPen: data.pen);
    }
    try {
      _observer?.onLog(data);
    } on Object {
      reportFailure('Talker output failed');
    }
    try {
      _events.add(data);
    } on Object {
      reportFailure('Log stream failed');
    }
    if (_consoleEnabled) {
      try {
        output(data.generateTextMessage());
      } on Object {
        reportFailure('Console output failed');
      }
    }
  }

  void _emit(Object? message, talker.LogLevel level, Object? error, StackTrace? stackTrace, {talker.AnsiPen? pen}) {
    final isolate = context();
    final time = clock.now();
    String text;
    try {
      text = message is Map || message is Iterable<Object?> || message is FormData
          ? sanitizer.encode(message)
          : message?.toString() ?? '';
    } on Object {
      text = '<unavailable>';
      reportFailure('Log formatting failed');
    }
    write(
      Observation(
        level: fromTalkerLevel(level),
        message: text,
        isolate: isolate,
        time: time,
        error: error,
        stackTrace: stackTrace,
      ),
      pen: pen,
    );
  }

  @override
  void log(
    Object? message, {
    talker.LogLevel logLevel = talker.LogLevel.debug,
    Object? exception,
    StackTrace? stackTrace,
    talker.AnsiPen? pen,
  }) => _emit(message, logLevel, exception, stackTrace, pen: pen);

  @override
  void logCustom(talker.TalkerLog log) {
    final isolate = context();
    final time = clock.now();
    try {
      final message = log.generateTextMessage(timeFormat: settings.timeFormat);
      write(
        Observation(
          level: fromTalkerLevel(log.logLevel ?? talker.LogLevel.debug),
          message: message,
          isolate: isolate,
          time: time,
        ),
        key: log.key,
        title: log.title,
        pen: log.pen,
      );
    } on Object {
      reportFailure('Custom log formatting failed');
      write(Observation(level: LogLevel.debug, message: '<unavailable custom log>', isolate: isolate, time: time));
    }
  }

  @override
  void handle(Object exception, [StackTrace? stackTrace, Object? msg]) =>
      _emit(msg, talker.LogLevel.error, exception, stackTrace);
  @override
  void verbose(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.verbose, exception, stackTrace);
  @override
  void debug(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.debug, exception, stackTrace);
  @override
  void info(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.info, exception, stackTrace);
  @override
  void warning(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.warning, exception, stackTrace);
  @override
  void error(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.error, exception, stackTrace);
  @override
  void critical(Object? msg, [Object? exception, StackTrace? stackTrace]) =>
      _emit(msg, talker.LogLevel.critical, exception, stackTrace);

  @override
  Stream<talker.TalkerData> get stream => _events.stream;

  @override
  List<talker.TalkerData> get history => List.unmodifiable(_records);
  @override
  void cleanHistory() => _records.clear();
  @override
  List<Observation> last({required int limit, LogLevel minimumLevel = LogLevel.verbose}) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    final eligible = _records.where((entry) => entry.observation.level.index >= minimumLevel.index).toList();
    return eligible
        .skip((eligible.length - limit).clamp(0, eligible.length))
        .map((entry) => entry.observation)
        .toList();
  }

  @override
  void configure({
    talker.TalkerLogger? logger,
    talker.TalkerSettings? settings,
    talker.TalkerObserver? observer,
    talker.TalkerFilter? filter,
    talker.TalkerErrorHandler? errorHandler,
    talker.TalkerHistory? history,
  }) {
    if (logger != null || history != null || errorHandler != null || filter != null) {
      throw UnsupportedError('Use Config for filters; Observatory owns the logger, history and error preparation');
    }
    if (settings != null) _consoleEnabled = settings.useConsoleLogs;
    _observer = observer ?? _observer;
    super.configure(
      settings: settings?.copyWith(useConsoleLogs: false, useHistory: false),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cleanHistory();
    disable();
    await _events.close();
  }
}

final class _ObservationLog extends talker.TalkerLog {
  final Observation observation;
  final LogSanitizer sanitizer;
  _ObservationLog(this.observation, this.sanitizer, {super.key, super.title, super.pen})
    : super(
        sanitizer.clip(observation.prefixedMessage),
        logLevel: toTalkerLevel(observation.level),
        time: observation.time,
      );

  @override
  String generateTextMessage({talker.TimeFormat timeFormat = talker.TimeFormat.timeAndSeconds}) =>
      sanitizer.clip(observation.prefixedMessage);
}

talker.LogLevel toTalkerLevel(LogLevel level) => switch (level) {
  LogLevel.verbose => talker.LogLevel.verbose,
  LogLevel.debug => talker.LogLevel.debug,
  LogLevel.info => talker.LogLevel.info,
  LogLevel.warning => talker.LogLevel.warning,
  LogLevel.error => talker.LogLevel.error,
  LogLevel.critical => talker.LogLevel.critical,
};

LogLevel fromTalkerLevel(talker.LogLevel level) => switch (level) {
  talker.LogLevel.verbose => LogLevel.verbose,
  talker.LogLevel.debug => LogLevel.debug,
  talker.LogLevel.info => LogLevel.info,
  talker.LogLevel.warning => LogLevel.warning,
  talker.LogLevel.error => LogLevel.error,
  talker.LogLevel.critical => LogLevel.critical,
};
