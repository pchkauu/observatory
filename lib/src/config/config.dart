import 'package:observatory/src/feature/_common/domain/log_level.dart';
import 'package:observatory/src/feature/_common/domain/policies/observation_filter.dart';
import 'package:observatory/src/feature/_common/domain/policies/redaction_policy.dart';
import 'package:package_context/package_context.dart' as package_context;
import 'package:talker_bloc_effects/talker_bloc_effects.dart';

final class Config extends package_context.PackageConfig {
  final ObservationFilter filter;
  final HttpLogSpec httpLog;
  final TalkerBlocEffectsSettings blocEffects;
  final RedactionPolicy redaction;
  final int historyLimit;
  final SentrySpec sentry;

  const Config({
    this.filter = const ObservationFilter.disabled(),
    this.httpLog = const HttpLogSpec(),
    this.blocEffects = const TalkerBlocEffectsSettings(),
    this.redaction = const RedactionPolicy(),
    this.historyLimit = 1000,
    this.sentry = const SentrySpec.disabled(),
  });
}

final class HttpLogSpec {
  final bool printHeaders;
  final bool printBody;

  const HttpLogSpec({
    this.printHeaders = false,
    this.printBody = false,
  });

  const HttpLogSpec.detailed() : printHeaders = true, printBody = true;
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

  void validate() {
    if (sampleRate < 0 || sampleRate > 1 || !sampleRate.isFinite) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be between 0 and 1');
    }
    if (maxBreadcrumbs < 0 || logsMaxBreadcrumbs < 0 || dedupeMaxEntries < 0 || dedupeTtl.isNegative) {
      throw ArgumentError('Sentry limits must not be negative');
    }
  }
}
