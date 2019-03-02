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
    _err(e, s);
    return 'Something went wrong 😤';
  }
}

Future<void> _basicTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> flushFunc(List<Map<String, dynamic>> list) async {
    try {
      debugPrint('flush list: ${list.length}');
      target.addAll(list.map((val) => val['val'] as int));
    } catch(e, s) {
      _err(e, s);
    }
  }

  final pq = PersistentQueue('pq',
    flushAt: testLen ~/ 5,
    flushFunc: flushFunc,
    maxLength: testLen * 2,
    errFunc: _err,
    noReload: true);

  for (int i = testLen; i > 0; --i) {
    final int val = Random().nextInt(4294967296);
    source.add(val);
    pq.push(<String, dynamic>{'val': val});
  }
  debugPrint('all data pushed');

  // polling
  int oldLen = -1, n = 0;
  while(target.length != source.length || n > 500000000) {
    n++;
    if (pq.length != oldLen && pq.length % 10 == 0) {
      debugPrint('${target.length} - ${pq.length}');
      oldLen = pq.length;
      continue;
    }
    await Future<void>.delayed(Duration(milliseconds: 1));
  }

  _assert(target.length == source.length);
  for (int i = source.length - 1; i >= 0; --i) {
    _assert(source[i] == target[i]);
  }
  debugPrint('pqp ${pq.length}');
  debugPrint('${source.length} / ${target.length}');

  await pq.destroy();
  debugPrint('queue works!');
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
void _err(dynamic err, [StackTrace stack]) => debugPrint('$err\n$stack');
