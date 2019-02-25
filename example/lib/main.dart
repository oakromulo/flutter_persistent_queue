import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(_MyApp());

class _MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _runTests(),
      builder: (context, snapshot) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(snapshot.data.toString() ?? 'hold on'),
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
    return 'Queue works 😀';
  } catch (e, s) {
    print('Exception:\n $e');
    print('Stack trace:\n $s');
    return 'Something went wrong 😤';
  }
}

Future<void> _basicTest() async {
  final pq = PersistentQueue(filename: 'pq', flushAt: 2000);
  print('queue instantiated');

  await pq.setup(noReload: true);
  print('queue ready? ${pq.ready ? 'YES' : 'NO'}');

  final Set<int> sourceSet = Set(), targetSet = Set();
  for (int i = 1000; i > 0; --i) {
    final int val = Random().nextInt(4294967296);
    sourceSet.add(val);
    await pq.push(<String, dynamic>{'val': val});
  }
  print('queue loaded, ${pq.length} elements');

  await pq.flush((list) async {
    targetSet.addAll(list.map((val) => val['val'] as int));
  });
  print('queue flushed');

  final sourceList = sourceSet.toList(), targetList = targetSet.toList();
  sourceList.sort();
  targetList.sort();

  _assert(sourceList.length == targetList.length);
  for (int i = sourceList.length - 1; i >= 0; --i) {
    _assert(sourceList[i] == targetList[i]);
  }
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
