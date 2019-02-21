// ignore_for_file: strong_mode_implicit_dynamic_type

import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(_MyApp());

Future<void> _assert() async {
  print('assertions started');

  print('queue instantiated');
  final pq = PersistentQueue(filename: 'pq', flushAt: 100000);
  await pq.setup();
  print('queue setup');

  await pq.flush();
  print('queue ready');

  final Set<int> source = Set(), target = Set();
  for (int i = 1000; i > 0; --i) {
    final int val = Random().nextInt(4294967296);
    source.add(val);
    await pq.push(<String, dynamic>{ 'val': val });
  }
  print('queue loaded');

  await pq.flush((list) async {
    target.addAll(list.map((val) => val['val'] as int));
  });
  print('queue cleared');

  final sourceList = source.toList(), targetList = target.toList();
  sourceList.sort();
  targetList.sort();
  assert(IterableEquality().equals(sourceList, targetList));

  print('queue assertion finished');
}

class _MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    _assert();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Please check the debug console'),
        ),
      ),
    );
  }
}
