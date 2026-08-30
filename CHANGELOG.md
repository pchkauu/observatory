## 0.1.0

- Initialize with `initPackage` (`Config` values + host `Talker`) and
  `Observatory.start` once per isolate.
- Expose static `record`, `capture`, `bindUser`, `bindDevice`, and `attachTo`
  so any library can log after start.
- Depend on Talker, Sentry, Bloc, and Dio again. The package owns the
  interceptor, Bloc observer, Sentry init, and log screen.
- Keep incident policies in domain. Host still owns Talker construction and
  Sentry DSN values.
- Require Dart `^3.13.2`, Flutter `>=3.47.2`, and `package_context` `^2.0.0`.
