// ignore_for_file: unawaited_futures, public_member_api_docs
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

Future<List<String>> example() async {
  final persistedValues = Set<String>();
  int initCnt, autoFlushCnt = 0, pushCnt = 0;

  List<String> strListFromMapList(List<Map<String, dynamic>> list) =>
      list.map<String>((v) => '${v['μs']}').toList();

  // instantiate queue and define implicit flush to fill persistedValues
  final pq = PersistentQueue('pq', flushAt: 12, onFlush: (list) async {
    persistedValues.addAll(strListFromMapList(list));
    autoFlushCnt += list.length;
  });

  // print the number of persisted items from previous run
  await pq.ready.then((_) => initCnt = pq.length);

  // read old elements before adding new ones, without dequeueing
  persistedValues.addAll(strListFromMapList(await pq.toList(growable: false)));

  // enqueue a pseudo-random amount of new items to the queue, without awaiting
  for (int i = 0; i < 36; ++i) {
    final int microseconds = DateTime.now().microsecondsSinceEpoch;
    if (microseconds % 10 > 0) continue;
    pq.push(<String, dynamic>{'μs': '$microseconds'});
    ++pushCnt;
  }

  // print execution stats before destroying the queue
  print('''\t
    items reloaded from previous run: $initCnt
    items to persist until next run: ${await pq.futureLength}
    items read from the queue: ${persistedValues.length}
    items flushed from the queue: $autoFlushCnt
    items written to the queue: $pushCnt
  ''');

  await pq.destroy();
  print('the queue is gone');

  // forward all strings loaded from the queue to the UI
  return persistedValues.toList(growable: false)..sort();
}

void main() => runApp(ExampleApp());

class ExampleApp extends StatelessWidget {
  @override
  Widget build(_) => FutureBuilder(future: example(), builder: app);
}

Widget app(BuildContext context, AsyncSnapshot<dynamic> snapshot) =>
    MaterialApp(home: home(snapshot));

Widget home(AsyncSnapshot<dynamic> snapshot) =>
    Scaffold(appBar: AppBar(title: Text('Example')), body: body(snapshot));

Widget body(AsyncSnapshot<dynamic> snapshot) {
  if (snapshot.data == null) return Center(child: CircularProgressIndicator());
  final children = (snapshot.data as List<String>).map<Widget>((String s) {
    return ListTile(leading: Icon(Icons.grade), title: Text(s.toString()));
  }).toList();
  return ListView(children: children);
}
