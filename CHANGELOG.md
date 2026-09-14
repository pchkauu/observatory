# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 3.0.1 - 2026-09-14

### Changed

- Document every public package declaration and member.
- Adopt automatic trailing-comma formatting across library, test, and example sources.

## 3.0.0 - 2026-09-14

### Changed

- Replace `ObservatoryThread` and the `thread` startup argument with automatic `launch_mode` detection.
- Use `SentryFlutter.init` for foreground work and `Sentry.init` for background and computational isolates.
- Make `Config` a `PackageConfig` and refresh internal package context across runtime restarts.
- Reorganize package internals under `feature/_common` by application, domain, infrastructure, and presentation.
- Upgrade `domain_error` to 3.0.0 and retain its `cause` and `typeIdentifier` data.
- Upgrade `package_context` to 2.2.0.

### Added

- Route `bloc_effects` through the managed Talker with `talker_bloc_effects` settings and observer forwarding.
- Preserve launch mode and zone context for Bloc/Cubit and standalone effects.

## 2.0.0 - 2026-09-13

### Changed

- Replace package initialization, startup and zone entry with `Observatory.run`.
- Own one shared Talker per isolate and add `thread(zoneName)` to all connected log sources.
- Capture `print` and `debugPrint` as ordinary info records; support nested operation zones.
- Share a bounded, sanitized history between the log screen and Sentry breadcrumbs.
- Preserve Sentry operation messages and exception chains; deduplicate by identity and location.
- Move redaction to `Config`; remove `Dependencies`, `package_context` and `disabledBlocLogs`.
- Make Dio attachment idempotent and restore owned handlers through `Observatory.close`.
- Keep local logging and application startup available when Sentry initialization fails.
- Redesign README diagrams around the shared log stream, incident routing and isolate lifecycle.

### Added

- Common URI, header, JSON, FormData and Sentry sanitization with bounded formatting.
- Regression tests for integration, lifecycle, isolates, privacy and local Sentry transport.
- GitHub Actions analysis, formatting, tests and package validation.

## 1.0.1 - 2026-08-30

### Added

- README diagrams for startup flow, `record` vs `capture`, and isolate-aware logs.
- PNG assets only (`hero`, `flow`, `safety`); HTML sources are not shipped.

## 1.0.0 - 2026-08-30

### Added

- `initPackage` with `Config` values (filter, HTTP log, Bloc skip list, Sentry) and a host-provided `Talker` in `Dependencies`.
- `Observatory.start` once per isolate, then static `record`, `capture`, `bindUser`, `bindDevice`, and `attachTo`.
- Isolate-aware Talker logs, Sentry capture with stable titles, dedupe, and log breadcrumbs.
- Safe Dio interceptor with header and body redaction, plus a Bloc observer.
- `Observatory.runZoned`, Flutter and platform error hooks, navigator observers, `ObservatoryLogScreen`, and `ObservatoryWidget`.
- Domain policies: `ObservationFilter`, `RedactionPolicy`, and `DedupePolicy`.
- Dart `^3.13.2`, Flutter `>=3.47.2`, and `package_context` `^2.0.0`.
