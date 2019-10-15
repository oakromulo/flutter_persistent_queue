// ignore_for_file: unawaited_futures, public_member_api_docs
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

Future<List<String>> example() async {
  final persistedValues = <String>{};

  const int flushAt = 12;

  int autoFlushCnt = 0, pushCnt = 0;

  List<String> toStrList(List<dynamic> list) =>
      list.map<String>((dynamic v) => '${v['μs']}').toList();

  // instantiate queue and define implicit flush to fill [persistedValues]
  final pq = PersistentQueue('pq', flushAt: flushAt, onFlush: (list) async {
    persistedValues.addAll(toStrList(list));

    autoFlushCnt += list.length;
    print('# of FLUSHED elements: ${list.length}');

    return true;
  });

  // register # of persisted items from previous run
  final initCnt = await pq.length;

  // preview old elements before adding new ones, without dequeueing
  persistedValues.addAll(toStrList(await pq.toList()));

  // enqueue a random-ish amount of values, without awaiting
  for (int i = 0; i < 36; ++i) {
    final int microseconds = DateTime.now().microsecondsSinceEpoch;

    if (microseconds % 10 > 0) {
      continue;
    }

    pq.push({'μs': '$microseconds'});
    ++pushCnt;
  }

  print('''\t
    items reloaded from previous run: $initCnt
    items left due to persist until next run: ${await pq.length}
    items read from the queue: ${persistedValues.length}
    items flushed from the queue: $autoFlushCnt
    items written to the queue: $pushCnt
    queue configured to flush at: $flushAt
  ''');

  await pq.destroy();
  print('the queue is gone');

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
  if (snapshot.data == null) {
    return Center(child: CircularProgressIndicator());
  }

  final children = (snapshot.data as List<String>)
      .map<Widget>((s) => ListTile(leading: Icon(Icons.grade), title: Text(s)))
      .toList();

  return ListView(children: children);
}
