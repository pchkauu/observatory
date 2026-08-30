import 'package:observatory/src/feature/_common/domain/log_level.dart';
import 'package:observatory/src/feature/_common/domain/policies/observation_filter.dart';
import 'package:observatory/src/feature/_common/domain/policies/redaction_policy.dart';
import 'package:package_context/package_context.dart' as package_context;

final class Config extends package_context.PackageConfig {
  final ObservationFilter filter;
  final HttpLogSpec httpLog;
  final List<String> disabledBlocLogs;
  final SentrySpec sentry;

  const Config({
    this.filter = const ObservationFilter.disabled(),
    this.httpLog = const HttpLogSpec(),
    this.disabledBlocLogs = const [],
    this.sentry = const SentrySpec.disabled(),
  });
}

final class HttpLogSpec {
  final bool printHeaders;
  final bool printBody;
  final RedactionPolicy redaction;

  const HttpLogSpec({
    this.printHeaders = false,
    this.printBody = false,
    this.redaction = const RedactionPolicy(),
  });

  const HttpLogSpec.detailed({
    this.redaction = const RedactionPolicy(),
  }) : printHeaders = true,
       printBody = true;
}

final class SentrySpec {
  final bool enabled;
  final String appPackageName;
  final String dsn;
  final String environment;
  final String release;
  final String dist;
  final double sampleRate;
  final int maxBreadcrumbs;
  final bool attachLogs;
  final LogLevel logsLevel;
  final int logsMaxBreadcrumbs;
  final bool attachScreenshot;
  final Duration dedupeTtl;
  final int dedupeMaxEntries;
  final bool anrEnabled;
  final Duration anrTimeoutInterval;
  final bool enableAppHangTracking;
  final Duration appHangTimeoutInterval;

  const SentrySpec({
    required this.enabled,
    required this.appPackageName,
    required this.dsn,
    required this.environment,
    required this.release,
    required this.dist,
    required this.sampleRate,
    required this.attachScreenshot,
    required this.attachLogs,
    required this.logsMaxBreadcrumbs,
    required this.logsLevel,
    required this.maxBreadcrumbs,
    required this.dedupeTtl,
    required this.dedupeMaxEntries,
    required this.anrEnabled,
    required this.anrTimeoutInterval,
    required this.enableAppHangTracking,
    required this.appHangTimeoutInterval,
  });

  const SentrySpec.disabled()
    : enabled = false,
      appPackageName = '',
      dsn = '',
      environment = '',
      release = '',
      dist = '',
      sampleRate = 0,
      attachScreenshot = false,
      attachLogs = false,
      logsMaxBreadcrumbs = 0,
      logsLevel = LogLevel.verbose,
      maxBreadcrumbs = 0,
      dedupeTtl = Duration.zero,
      dedupeMaxEntries = 0,
      anrEnabled = false,
      anrTimeoutInterval = const Duration(seconds: 5),
      enableAppHangTracking = false,
      appHangTimeoutInterval = const Duration(seconds: 2);
}
