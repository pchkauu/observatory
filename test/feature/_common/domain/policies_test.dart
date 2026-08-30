import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/src/feature/_common/domain/_barrel.dart';

void main() {
  group('IsolateContext', () {
    test('normalizes empty and long zone names', () {
      expect(IsolateContext.normalizeZoneName('  '), 'unspecified');
      expect(
        IsolateContext.normalizeZoneName('abcdefghijklmnopqrstuvwxyz'),
        'abcdefghijklmnopqrst',
      );
    });
  });

  group('ObservationFilter', () {
    test('allows everything when disabled', () {
      const filter = ObservationFilter.disabled();
      expect(filter.allowsLog('secret'), isTrue);
      expect(filter.allowsHttpUrl(Uri.parse('https://blocked.test')), isTrue);
    });

    test('excludes matching logs and urls', () {
      final filter = ObservationFilter(
        enabled: true,
        excludedLogs: const ['secret'],
        excludedHttpUrls: [RegExp('blocked')],
        excludedBlocTypes: const ['SkipBloc'],
      );
      expect(filter.allowsLog('secret token'), isFalse);
      expect(filter.allowsHttpUrl(Uri.parse('https://api.test/blocked')), isFalse);
      expect(filter.allowsBlocType('SkipBloc'), isFalse);
    });
  });

  group('DedupePolicy', () {
    test('drops repeats inside ttl and allows after expiry', () {
      final clock = _MutableClock(DateTime.utc(2026));
      final policy = DedupePolicy(
        ttl: const Duration(minutes: 1),
        maxEntries: 10,
        clock: clock,
      );

      expect(policy.allow('StateError:Bad state'), isTrue);
      expect(policy.allow('StateError:Bad state'), isFalse);
      clock.value = clock.value.add(const Duration(minutes: 2));
      expect(policy.allow('StateError:Bad state'), isTrue);
    });
  });

  group('ErrorIdentity', () {
    test('appends type metadata once', () {
      expect(
        ErrorIdentity.formatLogMessage('Sync failed', describedType: 'DioException'),
        'Sync failed\nerror.type=DioException',
      );
      expect(
        ErrorIdentity.formatLogMessage(
          'Sync failed\nerror.type=DioException',
          describedType: 'DioException',
        ),
        'Sync failed\nerror.type=DioException',
      );
    });

    test('describes unknown errors without leaking instance dumps', () {
      expect(ErrorIdentity.describeUnknown(null), isNull);
      expect(ErrorIdentity.describeUnknown(Object()), 'unknown');
    });

    test('reads a readable in-app location from frames', () {
      expect(
        ErrorIdentity.locationFrom(
          frames: const [
            StackFrameView(
              inApp: true,
              fileName: 'sync.dart',
              function: 'refresh',
              lineNo: 12,
            ),
          ],
          appPackageName: 'mobile',
          preferFileLine: false,
        ),
        'refresh.12',
      );
    });
  });

  group('RedactionPolicy', () {
    test('matches headers case-insensitively', () {
      const policy = RedactionPolicy();
      expect(policy.isSensitiveHeader('Authorization'), isTrue);
      expect(policy.isSensitiveHeader('x-api-key'), isTrue);
      expect(policy.isSensitiveHeader('X-Request-Id'), isFalse);
    });

    test('matches body keys by normalized substring', () {
      const policy = RedactionPolicy();
      expect(policy.isSensitiveBodyKey('firebaseToken'), isTrue);
      expect(policy.isSensitiveBodyKey('private_key'), isTrue);
      expect(policy.isSensitiveBodyKey('name'), isFalse);
    });
  });
}

final class _MutableClock implements ObservationClock {
  DateTime value;

  _MutableClock(this.value);

  @override
  DateTime now() => value;
}
