import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(_MyApp());

class _MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _runTests(),
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

Future<String> _runTests() async {
  try {
    await _basicTest();
    return 'Queue works! 😀';
  } catch (e, s) {
    _onError(e, s);
    return 'Something went wrong 😤';
  }
}

Future<void> _basicTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> onFlush(List<Map<String, dynamic>> list) async {
    try {
      debugPrint('regular flush: ${list.length}');
      target.addAll(list.map((val) => val['val'] as int));
    } catch(e, s) {
      _onError(e, s);
    }
  }

  final pq = PersistentQueue('pq',
    flushAt: testLen ~/ 5,
    onFlush: onFlush,
    onReset: () async => debugPrint('queue reset!'),
    maxLength: testLen * 2,
    onError: _onError,
    noReload: true);

  for (int i = testLen; i > 0; --i) {
    final int val = Random().nextInt(4294967296);
    source.add(val);
    pq.push(<String, dynamic>{'val': val});
  }
  debugPrint('all data pushed');

  Future<void> finalFlush(List<Map<String, dynamic>> list) async {
    try {
      debugPrint('final flush: ${list.length}');
      target.addAll(list.map((val) => val['val'] as int));
    } catch(e, s) {
      _onError(e, s);
    }
  }
  pq.flush(finalFlush);
  debugPrint('final flush scheduled');

  bool hasReset = false;
  pq.reset(() async => hasReset = true);
  debugPrint('final reset scheduled');

  // polling
  int oldLen = -1;
  for (int i = 0; !hasReset && i < 30000; ++i) {
    if (pq.length != oldLen && pq.length % 10 == 0) {
      debugPrint('${target.length} - ${pq.length}');
      oldLen = pq.length;
    }
    await Future<void>.delayed(Duration(milliseconds: 1));
  }

  _assert(pq.length == 0);
  _assert(target.length == source.length);
  for (int i = testLen - 1; i >= 0; --i) _assert(source[i] == target[i]);

  await pq.destroy();
  debugPrint('queue works!');
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
void _onError(dynamic err, [StackTrace stack]) => debugPrint('$err\n$stack');
