// ignore_for_file: unawaited_futures
import 'dart:math';
import 'package:flutter/foundation.dart';
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
    await _unawaitedTest().timeout(Duration(seconds: 30));
    await _sequentialTest().timeout(Duration(seconds: 30));
    const msg = 'Queue works! 😀';
    debugPrint(msg);
    return msg;
  } catch (e, s) {
    debugPrint('$e\n$s');
    const msg = 'Something went wrong 😤';
    debugPrint(msg);
    return msg;
  }
}

Future<void> _unawaitedTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> flushAction(List<Map<String, dynamic>> list) async =>
      target.addAll(list.map((v) => v['v'] as int));

  final pq = PersistentQueue('_unawaited_test_',
      flushAt: testLen ~/ 20,
      maxLength: testLen * 2,
      onFlush: flushAction);

  await pq.flush((_) async => debugPrint('queue cleared for unawaited test'));
  for (int i = testLen; i > 0; --i) {
    final v = Random().nextInt(4294967295);
    source.add(v);
    pq.push(<String, dynamic>{'v': v});
  }
  debugPrint('all data pushed to queue');

  bool hasReset = false;
  pq.flush((list) => flushAction(list).then((_) { hasReset = true; }));
  debugPrint('final flush scheduled with control flag');

  int oldLen = -1;
  while (!hasReset) {
    if (pq.length != oldLen && pq.length % 100 == 0) {
      debugPrint('polling: ${target.length} - ${pq.length}');
      oldLen = pq.length;
    }
    await Future<void>.delayed(Duration(microseconds: 100));
  }
  debugPrint('polling finished');

  await _finalize(pq, source, target);
}

Future<void> _sequentialTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> flushAction(List<Map<String, dynamic>> list) async {
    target.addAll(list.map((v) => v['v'] as int));
    debugPrint('flush: ${target.length} / $testLen');
  }

  final pq = PersistentQueue('_regular_test_',
      flushAt: testLen ~/ 20,
      maxLength: testLen * 2,
      onFlush: flushAction);

  await pq.flush((_) async => debugPrint('queue cleared for sequential test'));
  for (int i = testLen; i > 0; --i) {
    final v = Random().nextInt(4294967295);
    source.add(v);
    await pq.push(<String, dynamic>{'v': v});
  }
  await pq.flush();
  debugPrint('queue operations complete');

  await _finalize(pq, source, target);
}

Future<void> _finalize(PersistentQueue pq, List<int> source, List<int> target) {
  _assert(pq.length == 0);
  _assert(target.length == source.length);
  for (int i = source.length - 1; i >= 0; --i) _assert(source[i] == target[i]);
  return pq.destroy();
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
