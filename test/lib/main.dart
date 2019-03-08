/// @nodoc
// ignore_for_file: unawaited_futures, public_member_api_docs
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String txt1 = '', txt2 = '';
  bool unwaitEnabled = true, seqEnabled = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Text('UNAWAITED TEST'),
              Text(txt1, key: Key('txt1')),
              Divider(),
              Text('SEQUENTIAL TEST'),
              Text(txt2, key: Key('txt2'))
            ],
          ),
        ),
        appBar: AppBar(title: Text('Load Test')),
        bottomNavigationBar: BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Unawaited Test'),
              IconButton(
                key: Key('unwaited'),
                icon: Icon(Icons.grade),
                onPressed: () {
                  if (!unwaitEnabled) return;
                  unwaitEnabled = false;
                  _unawaitTest()
                    .then((res) => setState(() => txt1 = res))
                    .timeout(Duration(seconds: 120))
                    .catchError((dynamic e) => setState(() => txt1 = '$e'))
                    .whenComplete(() => setState(() => unwaitEnabled = true));
                }
              ),
              Text('Sequential Test'),
              IconButton(
                key: Key('sequential'),
                icon: Icon(Icons.grade),
                onPressed: () {
                  if (!seqEnabled) return;
                  seqEnabled = false;
                  _sequentialTest()
                    .then((res) => setState(() => txt2 = res))
                    .timeout(Duration(seconds: 120))
                    .catchError((dynamic e) => setState(() => txt2 = '$e'))
                    .whenComplete(() => setState(() => seqEnabled = true));
                }
              )
            ],
          )
        ),
      ),
    );
  }
}

Future<String> _unawaitTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> flushAction(List<Map<String, dynamic>> list) async =>
      target.addAll(list.map((v) => v['v'] as int));

  final pq = PersistentQueue('_unawaited_test_',
      flushAt: testLen ~/ 20, maxLength: testLen * 2, onFlush: flushAction);

  await pq.flush((_) async => debugPrint('queue cleared for unawait test'));
  for (int i = testLen; i > 0; --i) {
    final v = Random().nextInt(4294967295);
    source.add(v);
    pq.push(<String, dynamic>{'v': v});
  }
  debugPrint('all data pushed to queue');

  bool hasReset = false;
  pq.flush((list) => flushAction(list).then((_) => hasReset = true));
  debugPrint('final flush scheduled with control flag');

  int oldLen = -1;
  while (!hasReset) {
    final int currLen = pq.length;
    if (currLen != oldLen && currLen % 100 == 0) {
      debugPrint('polling: ${target.length} - ${pq.length}');
      oldLen = currLen;
    }
    await Future<void>.delayed(Duration(microseconds: 100));
  }
  debugPrint('polling finished');

  await _finalize(pq, source, target);

  return 'unawaited test completed succesfully';
}

Future<String> _sequentialTest() async {
  const testLen = 10000;
  final source = <int>[], target = <int>[];

  Future<void> flushAction(List<Map<String, dynamic>> list) async {
    target.addAll(list.map((v) => v['v'] as int));
    debugPrint('flush: ${target.length} / $testLen');
  }

  final pq = PersistentQueue('_regular_test_',
      flushAt: testLen ~/ 20, maxLength: testLen * 2, onFlush: flushAction);

  await pq.flush((_) async => debugPrint('queue cleared for seq. test'));
  for (int i = testLen; i > 0; --i) {
    final v = Random().nextInt(4294967295);
    source.add(v);
    await pq.push(<String, dynamic>{'v': v});
  }
  await pq.flush();
  debugPrint('queue operations complete');

  await _finalize(pq, source, target);

  return 'sequential test completed succesfully';
}

Future<void> _finalize(PersistentQueue pq, List<int> src, List<int> tgt) async {
  _assert(pq.length == 0);
  _assert(tgt.length == src.length);
  for (int i = src.length - 1; i >= 0; --i) _assert(src[i] == tgt[i]);
  await pq.destroy();
}

void _assert(bool cta) {
  if (cta == true) return;
  throw Exception('TestFailed');
}
