import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('Load Test App', () {
    final txt1Finder = find.byValueKey('txt1');
    final txt2Finder = find.byValueKey('txt2');
    final unawaitedFinder = find.byValueKey('unawaited');
    final seqFinder = find.byValueKey('sequential');

    FlutterDriver driver;

    setUpAll(() async => driver = await FlutterDriver.connect());

    tearDownAll(() async {
      if (driver != null) await driver.close();
    });

    test('run sequential test', () async {
      await driver.tap(seqFinder);

      int i = 120;
      bool success = false;

      while (--i > 0) {
        final txt = await driver.getText(txt2Finder);
        if (txt.contains('success')) {
          success = true;
          break;
        } else {
          await Future<void>.delayed(Duration(seconds: 1));
        }
      }

      expect(success, true);
    });

    test('run unawaited test', () async {
      const testLen = 5000;

      await driver.tap(unawaitedFinder);

      final t0 = DateTime.now();
      DateTime t1;

      int i = 600;
      bool success = false;

      while (--i > 0) {
        final txt = await driver.getText(txt1Finder);

        if (txt.contains('success')) {
          t1 = DateTime.now();
          success = true;
          break;
        }

        await Future<void>.delayed(Duration(milliseconds: 100));
      }
      expect(success, true);

      final tput = testLen / t1.difference(t0).inSeconds;
      print('throughput: ${tput.toStringAsFixed(2)}');
      expect(tput, greaterThan(250.0));
    });
  });
}
