import 'package:observatory/src/feature/_common/domain/log_level.dart';
import 'package:observatory/src/feature/_common/domain/policies/observation_filter.dart';
import 'package:observatory/src/feature/_common/domain/policies/redaction_policy.dart';
import 'package:package_context/package_context.dart' as package_context;
import 'package:talker_bloc_effects/talker_bloc_effects.dart';

/// Defines filtering, storage, sanitization, integration, and Sentry behavior.
final class Config extends package_context.PackageConfig {
  /// Filters ordinary logs by message, HTTP URL, or exact BLoC type name.
  final ObservationFilter filter;

  /// Controls which HTTP request and response fields are logged.
  final HttpLogSpec httpLog;

  /// Controls logging for effects emitted through `bloc_effects`.
  final TalkerBlocEffectsSettings blocEffects;

  /// Sanitizes sensitive values before local storage or remote capture.
  final RedactionPolicy redaction;

  /// Maximum retained log entries; zero disables retention.
  final int historyLimit;

  /// Configures remote incident capture through Sentry.
  final SentrySpec sentry;

  /// Creates a configuration with local logging enabled and Sentry disabled.
  ///
  /// [historyLimit] must not be negative.
  const Config({
    this.filter = const ObservationFilter.disabled(),
    this.httpLog = const HttpLogSpec(),
    this.blocEffects = const TalkerBlocEffectsSettings(),
    this.redaction = const RedactionPolicy(),
    this.historyLimit = 1000,
    this.sentry = const SentrySpec.disabled(),
  });
}

/// Controls optional HTTP metadata in Dio logs.
final class HttpLogSpec {
  /// Whether sanitized request and response headers are included.
  final bool printHeaders;

  /// Whether sanitized request and response bodies are included.
  final bool printBody;

  /// Creates a minimal HTTP log specification.
  const HttpLogSpec({this.printHeaders = false, this.printBody = false});

  /// Creates a specification that includes sanitized headers and bodies.
  const HttpLogSpec.detailed() : printHeaders = true, printBody = true;
}

/// Defines Sentry initialization, attachments, breadcrumbs, and deduplication.
final class SentrySpec {
  /// Whether Observatory attempts to initialize Sentry.
  final bool enabled;

  /// Application package used to identify in-app stack frames.
  final String appPackageName;

  /// Sentry data source name.
  final String dsn;

  /// Deployment environment reported to Sentry.
  final String environment;

  /// Release identifier reported to Sentry.
  final String release;

  /// Distribution identifier reported to Sentry.
  final String dist;

  /// Fraction of events accepted by the Sentry SDK, from zero to one.
  final double sampleRate;

  /// Maximum breadcrumbs retained by the Sentry SDK.
  final int maxBreadcrumbs;

  /// Whether retained Observatory logs are attached as breadcrumbs.
  final bool attachLogs;

  /// Minimum severity for attached Observatory log breadcrumbs.
  final LogLevel logsLevel;

  /// Maximum Observatory log breadcrumbs added to an event.
  final int logsMaxBreadcrumbs;

  /// Whether Sentry may attach screenshots using its privacy defaults.
  final bool attachScreenshot;

  /// Time window during which matching incidents are suppressed.
  final Duration dedupeTtl;

  /// Maximum incident fingerprints retained for deduplication.
  final int dedupeMaxEntries;

  /// Whether Sentry application-not-responding tracking is enabled.
  final bool anrEnabled;

  /// Duration after which Sentry reports an application-not-responding event.
  final Duration anrTimeoutInterval;

  /// Whether Sentry application hang tracking is enabled.
  final bool enableAppHangTracking;

  /// Duration after which Sentry reports an application hang.
  final Duration appHangTimeoutInterval;

  /// Creates an enabled or disabled Sentry specification from explicit values.
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

  /// Creates a specification that performs no remote Sentry work.
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

  /// Validates sampling and bounded collection settings.
  ///
  /// Throws [ArgumentError] when a rate is outside zero to one or a limit is
  /// negative.
  void validate() {
    if (sampleRate < 0 || sampleRate > 1 || !sampleRate.isFinite) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be between 0 and 1');
    }
    if (maxBreadcrumbs < 0 || logsMaxBreadcrumbs < 0 || dedupeMaxEntries < 0 || dedupeTtl.isNegative) {
      throw ArgumentError('Sentry limits must not be negative');
    }
  }
}
