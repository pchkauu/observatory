# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 1.0.0 - 2026-08-30

### Added

- `initPackage` with `Config` values (filter, HTTP log, Bloc skip list, Sentry) and a host-provided `Talker` in `Dependencies`.
- `Observatory.start` once per isolate, then static `record`, `capture`, `bindUser`, `bindDevice`, and `attachTo`.
- Isolate-aware Talker logs, Sentry capture with stable titles, dedupe, and log breadcrumbs.
- Safe Dio interceptor with header and body redaction, plus a Bloc observer.
- `Observatory.runZoned`, Flutter and platform error hooks, navigator observers, `ObservatoryLogScreen`, and `ObservatoryWidget`.
- Domain policies: `ObservationFilter`, `RedactionPolicy`, and `DedupePolicy`.
- Dart `^3.13.2`, Flutter `>=3.47.2`, and `package_context` `^2.0.0`.
