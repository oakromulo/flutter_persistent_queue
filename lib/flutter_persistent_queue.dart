library flutter_persistent_queue;

import 'package:meta/meta.dart';
import 'package:localstorage/localstorage.dart';
import 'package:synchronized/synchronized.dart';

typedef AsyncFlushFunc = Future<void> Function(List<Map<String, dynamic>>);

typedef _StorageFunc = Future<void> Function(LocalStorage);
typedef _VoidAsyncFunc = Future<void> Function();

class PersistentQueue {
  PersistentQueue(
      {@required String filename,
      AsyncFlushFunc flushFunc,
      int flushAt = 100,
      Duration flushTimeout = const Duration(minutes: 5)})
      : _filename = filename,
        _flushFunc = flushFunc,
        _flushAt = flushAt,
        _flushTimeout = flushTimeout;

  final String _filename;
  final AsyncFlushFunc _flushFunc;
  final int _flushAt;
  final Duration _flushTimeout;
  final _queueLock = Lock(reentrant: true), _fileLock = Lock(reentrant: true);

  int _len;
  DateTime _deadline;
  bool _ready = false;

  int get length => _len;
  bool get ready => _ready;

  Future<void> setup() async {
    _ready = false;
    await _reload();
    _ready = true;
  }

  Future<void> push(Map<String, dynamic> value) async {
    await _queue(() async {
      await _write(value);
      if (_len == 1) _newDeadline();
      if (_len >= _flushAt || _deadlineExpired()) await flush();
    });
  }

  Future<void> flush([AsyncFlushFunc inputFunc]) async {
    await _queue(() async {
      final _flush = inputFunc ?? _flushFunc;
      await _flush(await _toList());
      await _reset();
    });
  }

  Future<void> _queue(_VoidAsyncFunc inputFunc) async {
    if (!_ready) throw Exception('PersistQueueNotReady');
    await _queueLock.synchronized(() async {
      await inputFunc();
    });
  }

  void _newDeadline() => _deadline = DateTime.now().toUtc().add(_flushTimeout);
  bool _deadlineExpired() => DateTime.now().toUtc().isAfter(_deadline);

  Future<List<Map<String, dynamic>>> _toList() async {
    final List<Map<String, dynamic>> li = List(_len);
    await _file((storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem(k.toString()) as Map<String, dynamic>;
      }
    });
    return li;
  }

  Future<void> _write(Map<String, dynamic> value) async {
    await _file((storage) async {
      await storage.setItem(_len.toString(), value);
      _len++;
    });
  }

  Future<void> _reload() async {
    await _file((storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem(_len.toString()) == null) break;
      }
      if (_len > 0) _newDeadline();
    });
  }

  Future<void> _reset() async {
    await _file((storage) async {
      await storage.clear();
      _len = 0;
    });
  }

  Future<void> _file(_StorageFunc inputFunc) async {
    await _fileLock.synchronized(() async {
      final storage = LocalStorage(_filename);
      await storage.ready;
      await inputFunc(storage);
    });
  }
}
