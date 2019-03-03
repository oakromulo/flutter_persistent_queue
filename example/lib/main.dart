import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(_MyApp());

class _MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _test(),
      builder: (context, snapshot) {
        final txt = snapshot.data == null ? 'Wait!' : snapshot.data as String;
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(txt),
            ),
          ),
        );
      },
    );
  }
}

Future<String> _test() async {
  try {
    const testLen = 10000;
    final source = <int>[], target = <int>[];

    final pq = PersistentQueue('pq',
        flushAt: testLen ~/ 10,
        maxLength: testLen * 2,
        onFlush: (list) async => target.addAll(list.map((v) => v['v'] as int)),
        onError: _printError,
        noReload: true);
    debugPrint('queue instantiated');

    for (int i = testLen; i > 0; --i) {
      final v = Random().nextInt(4294967295);
      source.add(v);
      pq.push(<String, dynamic>{'v': v});
    }
    pq.flush();
    debugPrint('all data pushed to queue and a final flush got scheduled');

    bool hasReset = false;
    pq.reset(() async => hasReset = true);
    debugPrint('final reset scheduled with control flag');

    // polling until final reset or timeout
    int oldLen = -1;
    for (int i = 0; !hasReset && i < 10000; ++i) {
      if (pq.length != oldLen && pq.length % 10 == 0) {
        debugPrint('${target.length} - ${pq.length}');
        oldLen = pq.length;
      }
      await Future<void>.delayed(Duration(milliseconds: 1));
    }
    debugPrint('polling finished');

    _assert(pq.length == 0);
    _assert(target.length == source.length);
    for (int i = testLen - 1; i >= 0; --i) _assert(source[i] == target[i]);
    debugPrint('all assertions passed');

    await pq.destroy();
    debugPrint('queue destroyed');

    const msg = 'Queue works! 😀';
    debugPrint(msg);
    return msg;
  } catch (e, s) {
    _printError(e, s);

    const msg = 'Something went wrong 😤';
    debugPrint(msg);
    return msg;
  }
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
void _printError(dynamic e, [StackTrace stack]) => debugPrint('$e\n$stack');
