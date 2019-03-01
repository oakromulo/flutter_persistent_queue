///
library flutter_persistent_queue;

import 'dart:async';
import 'package:localstorage/localstorage.dart';

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
    _buffer = _Buffer<_Event>(_onData);
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

  _Buffer<_Event> _buffer;
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
  Future destroy() => _buffer.destroy();

  ///
  int get bufferLength => _buffer.length;

  Future _onData(_Event event) {
    if (event.type == _EventType.FLUSH) return _onFlush(event);
    else if (event.type == _EventType.RELOAD) return _onReload(event);
    else if (event.type == _EventType.RESET) return _onReset(event);
    return _onPush(event);
  }

  Future _onPush(_Event event) async {
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

  Future _onFlush(_Event event) async {
    try {
      final AsyncFlushFunc _func = event.flush ?? flushFunc;
      if (_func != null) await _func(await _toList());
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
  Future _onReset([_Event event]) =>
    _file((LocalStorage storage) async {
      await storage.clear();
      _len = 0;
    });

  // may throw
  Future _toList() =>
    _file((LocalStorage storage) async {
      final li = List<Map<String, dynamic>>(_len);
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k') as Map<String, dynamic>;
      }
      return li;
    });

  // may throw
  Future _write(Map<String, dynamic> value) =>
    _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);
      _len++;
    });

  // may throw
  Future _file(_StorageFunc inputFunc) async {
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

class _Buffer<T> {
  _Buffer(Future Function(T) onData, [Function onError]) {
    _sub = _controller.stream.listen((T event) {
      _sub.pause(onData(event).catchError(onError).whenComplete(() => _len--));
    });
  }

  final _controller = StreamController<T>();
  StreamSubscription<T> _sub;
  int _len = 0;

  int get length => _len;

  void push(T event) {
    _len++;
    _controller.add(event);
  }

  Future destroy() async {
    await _sub.cancel();
    await _controller.close();
  }
}

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef AsyncFlushFunc = Future Function(List<Map<String, dynamic>>);

///
typedef ErrFunc = Function(dynamic error, [StackTrace stack]);

typedef _StorageFunc = Future Function(LocalStorage);