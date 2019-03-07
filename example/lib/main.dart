// ignore_for_file: unawaited_futures, public_member_api_docs
import 'package:flutter/material.dart';
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

void main() => runApp(ExampleApp());

class ExampleApp extends StatelessWidget {
  @override
  Widget build(_) => FutureBuilder(future: example(), builder: app);
}

Future<List<String>> example() async {
  final persistedList = <String>[];

  // instantiate queue and define implicit flush to fill the persistedList
  final pq = PersistentQueue('pq', flushAt: 10, onFlush: (list) async {
    persistedList.addAll(list.map<String>((v) => '${v['μs']}').toList());
  });

  // fill new data to be read on next app reload
  for (int i = 0; i < 10; ++i) await pq.push(<String, dynamic>{'μs': us()});

  // return old data
  return persistedList;
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

String us() => DateTime.now().microsecondsSinceEpoch.toString();
