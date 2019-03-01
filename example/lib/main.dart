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
  final pq = PersistentQueue('pq', flushAt: 100, errFunc: _err, noReload: true);
  
  const setLen = 50; 
  final Set<int> sourceSet = Set(), targetSet = Set();
  for (int i = setLen; i > 0; --i) {
    final int val = Random().nextInt(4294967296);
    sourceSet.add(val);
    pq.push(<String, dynamic>{'val': val});
  }
  print('all data pushed');

  pq.flush((list) async {
    targetSet.addAll(list.map((val) => val['val'] as int));
  });
  print('flush scheduled');

  // polling
  int oldLen = -1, n = 0;
  while(targetSet.length != setLen || n > 5000000) {
    n++;
    if (pq.length != oldLen) {
      print(pq.length);
      oldLen = pq.length;
    }
    await Future.delayed(Duration(microseconds: 1));
  }

  final sourceList = sourceSet.toList(), targetList = targetSet.toList();
  sourceList.sort();
  targetList.sort();

  _assert(sourceList.length == targetList.length);
  for (int i = sourceList.length - 1; i >= 0; --i) {
    _assert(sourceList[i] == targetList[i]);
  }

  print('queue works!');
}

void _assert(bool cta) => cta != true ? throw Exception('QueueFailed') : null;
void _err(dynamic err, [StackTrace stack]) => debugPrint('$err\n$stack');
