///
library flutter_persistent_queue;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:localstorage/localstorage.dart';

import './util/buffer.dart';

///
class PersistentQueue {
  ///
  PersistentQueue(this.filename,
      {this.errFunc,
      this.flushFunc,
      this.flushAt = 100,
      this.flushTimeout = const Duration(minutes: 5),
      int maxLength,
      bool noReload = false})
      : _maxLength = maxLength ?? flushAt * 5 {
    // init buffer
    _buffer = Buffer<_Event>(_onData);

    // start fresh or reload persisted state, according to [noReload]
    final setupEventType = noReload ? _EventType.RESET : _EventType.RELOAD;
    _buffer.push(_Event(setupEventType));
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

  // max number of queued items, either in-memory or on fs
  final int _maxLength;

  Buffer<_Event> _buffer;
  DateTime _deadline;
  int _len = 0;

  /// the current number of elements in non-volatile storage
  int get length => _len;

  /// the current number of in-memory elements
  int get bufferLength => _buffer.length;

  /// push a new [item] to the the in-memory buffer until it can go to the fs
  void push(Map<String, dynamic> item /*, [ErrFunc errFunc]*/) {
    if (_len + _buffer.length + 1 >= _maxLength) {
      throw 'PersistentQueueOverflow';
    }
    _buffer.push(_Event(_EventType.PUSH, item: item /*, onError: errFunc*/));
  }

  /// push a flush instruction to the end of the event buffer
  void flush([AsyncFlushFunc flushFunc /*, [ErrFunc errFunc]*/]) {
    const type = _EventType.FLUSH;
    final event = _Event(type, flush: flushFunc /*, onError: errFunc*/);
    _buffer.push(event);
  }

  /// deallocates queue resources (data already on the fs persists)
  Future<void> destroy() => _buffer.destroy();

  // buffer calls onData every time it's ready to process a new [_Event] and
  // then an event handler method gets executed according to [_Event.type]
  Future<void> _onData(_Event event) async {
    if (event.type == _EventType.FLUSH) {
      print('flush request');
      await _onFlush(event);
    } else if (event.type == _EventType.PUSH) {
      await _onPush(event);
    } else if (event.type == _EventType.RELOAD) {
      await _onReload(event);
    } else if (event.type == _EventType.RESET) {
      await _onReset(event);
    }
  }

  Future<void> _onPush(_Event event) async {
    try {
      await _write(event.item); // call event.onWrite?
      if (_len == 1) _deadline = _newDeadline(flushTimeout);
      if (_len >= flushAt || _isExpired(_deadline)) await _onFlush(event); // !!
    } catch (e, s) {
      debugPrint('push error: $e\n$s');
      /*final ErrFunc _func = event.onError ?? errFunc;
      if (_func != null) _func(e, s);*/
    }
  }

  Future<void> _onFlush(_Event event) async {
    try {
      print('flush attempt');
      final AsyncFlushFunc _func = event.flush ?? flushFunc;
      if (_func != null) await _func(await _toList());
      await _onReset(event);
    } catch (e, s) {
      debugPrint('flush error: $e\n$s');
      /*final ErrFunc _func = event.onError ?? errFunc;
      if (_func != null) _func(e, s);*/
    }
  }

  Future<void> _onReload(_Event event) async {
    await _file((LocalStorage storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem('$_len') == null) break;
      }
      if (_len > 0) _deadline = _newDeadline(flushTimeout);
    });
  }

  Future<void> _onReset(_Event event) async {
    await _file((LocalStorage storage) async {
      await storage.clear();
      _len = 0;
    });
  }

  Future<List<Map<String, dynamic>>> _toList() async {
    if (_len == null || _len < 1) return [];
    final li = List<Map<String, dynamic>>(_len);
    await _file((LocalStorage storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k') as Map<String, dynamic>;
      }
    });
    return li;
  }

  Future<void> _write(Map<String, dynamic> value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);
      _len++;
    });
  }

  Future<void> _file(_StorageFunc inputFunc) async {
    try {
      final storage = LocalStorage(filename);
      await storage.ready;
      await inputFunc(storage);
    } catch (e, s) {
      debugPrint('flush error: $e\n$s');
      //if (errFunc != null) errFunc(e, s);
    }
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

enum _EventType { FLUSH, PUSH, RELOAD, RESET }

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef AsyncFlushFunc = Future<void> Function(List<Map<String, dynamic>>);

///
typedef ErrFunc = Function(dynamic error, [StackTrace stack]);

typedef _StorageFunc = Future<void> Function(LocalStorage);
