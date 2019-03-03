///
library flutter_persistent_queue;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:localstorage/localstorage.dart' show LocalStorage;

import './classes/buffer.dart' show Buffer;
import './classes/queue_event.dart' show QueueEvent, QueueEventType;
import './typedefs/typedefs.dart' show OnFlush, StorageFunc, OnError;

///
class PersistentQueue {
  ///
  PersistentQueue(this.filename,
      {this.onError,
      this.onFlush,
      this.flushAt = 100,
      this.flushTimeout = const Duration(minutes: 5),
      int maxLength,
      bool noReload = false})
      : _maxLength = maxLength ?? flushAt * 5 {
    // init buffer
    _buffer = Buffer<QueueEvent>(_onData);

    // start fresh or reload persisted state, according to [noReload]
    final initType = noReload ? QueueEventType.RESET : QueueEventType.RELOAD;
    _buffer.push(QueueEvent(initType));
  }

  ///
  final String filename;

  ///
  final OnFlush onFlush;

  ///
  final OnError onError;

  ///
  final int flushAt;

  ///
  final Duration flushTimeout;

  // max number of queued items, either in-memory or on fs
  final int _maxLength;

  Buffer<QueueEvent> _buffer;
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
    const type = QueueEventType.PUSH;
    final event = QueueEvent(type, item: item /*, onError: errFunc*/);
    _buffer.push(event);
  }

  /// push a flush instruction to the end of the event buffer
  void flush([OnFlush flushFunc /*, [ErrFunc errFunc]*/]) {
    const type = QueueEventType.FLUSH;
    final event = QueueEvent(type, onFlush: flushFunc /*, onError: errFunc*/);
    _buffer.push(event);
  }

  /// deallocates queue resources (data already on the fs persists)
  Future<void> destroy() => _buffer.destroy();

  // buffer calls onData every time it's ready to process a new [_Event] and
  // then an event handler method gets executed according to [_Event.type]
  Future<void> _onData(QueueEvent event) async {
    if (event.type == QueueEventType.FLUSH) {
      print('flush request');
      await _onFlush(event);
    } else if (event.type == QueueEventType.PUSH) {
      await _onPush(event);
    } else if (event.type == QueueEventType.RELOAD) {
      await _onReload(event);
    } else if (event.type == QueueEventType.RESET) {
      await _onReset(event);
    }
  }

  Future<void> _onPush(QueueEvent event) async {
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

  Future<void> _onFlush(QueueEvent event) async {
    try {
      print('flush attempt');
      final OnFlush _func = event.onFlush ?? onFlush;
      if (_func != null) await _func(await _toList());
      await _onReset(event);
    } catch (e, s) {
      debugPrint('flush error: $e\n$s');
      /*final ErrFunc _func = event.onError ?? errFunc;
      if (_func != null) _func(e, s);*/
    }
  }

  Future<void> _onReload(QueueEvent event) async {
    await _file((LocalStorage storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem('$_len') == null) break;
      }
      if (_len > 0) _deadline = _newDeadline(flushTimeout);
    });
  }

  Future<void> _onReset(QueueEvent event) async {
    await _file((LocalStorage storage) async {
      try {
        _len = 0;
        await storage.clear(); // slow!!
      } catch (e, s) {
        debugPrint('reset error: $e\n$s');
        //if (errFunc != null) errFunc(e, s);
      }
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

  Future<void> _file(StorageFunc inputFunc) async {
    try {
      final storage = LocalStorage(filename);
      await storage.ready;
      await inputFunc(storage);
    } catch (e, s) {
      debugPrint('file error: $e\n$s');
      //if (errFunc != null) errFunc(e, s);
    }
  }

  DateTime _newDeadline(Duration flushTimeout) => _nowUtc().add(flushTimeout);
  bool _isExpired(DateTime deadline) => _nowUtc().isAfter(deadline);
  DateTime _nowUtc() => DateTime.now().toUtc();
}
