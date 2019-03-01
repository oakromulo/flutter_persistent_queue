///
library flutter_persistent_queue;

import 'package:localstorage/localstorage.dart';
import './util/buffer.dart';

///
class PersistentQueue {
  ///
  PersistentQueue(this.filename, {
    this.errFunc,
    this.flushFunc,
    this.flushAt = 100,
    this.flushTimeout = const Duration(minutes: 5),
    bool noReload = false
  }) {
    _buffer = Buffer<_Event>(_onData);
    if (noReload) _buffer.push(_Event(_EventType.RESET));
    else _buffer.push(_Event(_EventType.RELOAD));
  }

  ///
  final String filename;

  ///
  final AsyncFlushFunc flushFunc;

  ///
  final ErrFunc errFunc;

  ///
  final int flushAt;

  ///
  final Duration flushTimeout;

  Buffer<_Event> _buffer;
  DateTime _deadline;
  int _len = 0;

  ///
  int get length => _len;

  /// 
  void push(Map<String, dynamic> item, [ErrFunc errFunc]) {
    _buffer.push(_Event(_EventType.PUSH, item: item, onError: errFunc));
  }

  /// 
  void flush([AsyncFlushFunc flushFunc, ErrFunc errFunc]) {
    _buffer.push(_Event(_EventType.FLUSH, flush: flushFunc, onError: errFunc));
  }

  ///
  Future<void> destroy() => _buffer.destroy();

  ///
  int get bufferLength => _buffer.length;

  Future<void> _onData(_Event event) {
    if (event.type == _EventType.FLUSH) return _onFlush(event);
    else if (event.type == _EventType.RELOAD) return _onReload(event);
    else if (event.type == _EventType.RESET) return _onReset(event);
    return _onPush(event);
  }

  Future<void> _onPush(_Event event) async {
    try {
      await _write(event.item); // call event.onWrite?
      if (_len == 1) _deadline = _newDeadline(flushTimeout);
      if (_len >= flushAt || _isExpired(_deadline)) flush();

      // post_flush \/
      //if (_len >= _maxLength) throw Exception('QueueOverflow: $_filename');
    } catch (e, s) {
      final ErrFunc _func = event.onError ?? errFunc;
      if (_func != null) _func(e, s);
    }
  }

  Future<void> _onFlush(_Event event) async {
    try {
      final AsyncFlushFunc _func = event.flush ?? flushFunc;
      final myList = await _toList();
      if (_func != null) await _func(myList);
      await _onReset();
    } catch (e, s) {
      final ErrFunc _func = event.onError ?? errFunc;
      if (_func != null) _func(e, s);
    }
  }

  // MAY SERIOUSLY THROW
  Future<void> _onReload([_Event event]) =>
    _file((LocalStorage storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem('$_len') == null) break;
      }
      if (_len > 0) _deadline = _newDeadline(flushTimeout);
    });

  // may seriously throw
  Future<void> _onReset([_Event event]) =>
    _file((LocalStorage storage) async {
      await storage.clear();
      _len = 0;
    });

  // may throw
  Future<List<Map<String, dynamic>>> _toList() async {
    final li = List<Map<String, dynamic>>(_len);
    await _file((LocalStorage storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k') as Map<String, dynamic>;
      }
    });
    return li;
  }

  // may throw
  Future<void> _write(Map<String, dynamic> value) =>
    _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);
      _len++;
    });

  // may throw
  Future<void> _file(_StorageFunc inputFunc) async {
    final storage = LocalStorage(filename);
    await storage.ready;
    await inputFunc(storage);
  }

  DateTime _newDeadline(Duration flushTimeout) => _nowUtc().add(flushTimeout);
  bool _isExpired(DateTime deadline) => _nowUtc().isAfter(deadline);
  DateTime _nowUtc() => DateTime.now().toUtc();
}

class _Event {
  _Event(this.type, {this.item, this.flush, this.onError});
  final _EventType type;
  final Map<String, dynamic> item;
  final AsyncFlushFunc flush;
  final ErrFunc onError;
}

enum _EventType { PUSH, FLUSH, RELOAD, RESET }  

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef AsyncFlushFunc = Future<void> Function(List<Map<String, dynamic>>);

///
typedef ErrFunc = Function(dynamic error, [StackTrace stack]);

typedef _StorageFunc = Future<void> Function(LocalStorage);