import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';

void main() {
  test('creates the Flutter binding in the same zone as the body', () async {
    try {
      await Observatory.run<void>(
        config: const Config(),
        thread: ObservatoryThread.foreground,
        zoneName: 'main',
        body: () {
          expect(WidgetsBinding.instance.debugCheckZone('run body'), isTrue);
        },
      );
      await Observatory.close();
      await Observatory.run<void>(
        config: const Config(),
        thread: ObservatoryThread.foreground,
        zoneName: 'restart',
        body: () {
          expect(WidgetsBinding.instance.debugCheckZone('restarted body'), isTrue);
          Observatory.talker.info('restarted');
        },
      );
      expect(Observatory.talker.history.single.message, 'foreground(restart): restarted');
    } finally {
      await Observatory.close();
    }
  });
}
