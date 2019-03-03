///
library flutter_persistent_queue;

import 'dart:async' show Completer;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:localstorage/localstorage.dart' show LocalStorage;

import './classes/queue_buffer.dart' show QueueBuffer;
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
    _buffer = QueueBuffer<QueueEvent>(_onData);

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

  QueueBuffer<QueueEvent> _buffer;
  DateTime _deadline;
  int _len = 0;

  /// the current number of elements in non-volatile storage
  int get length => _len;

  /// the current number of in-memory elements
  int get bufferLength => _buffer.length;

  ///
  Future<void> push(Map<String, dynamic> item) {
    if (length >= _maxLength - 1) {
      throw 'PersistentQueueOverflow';
    }
    const type = QueueEventType.PUSH;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, item: item, completer: completer));
    return completer.future;
  }

  /// push a flush instruction to the end of the event buffer
  Future<void> flush([OnFlush onFlush]) {
    const type = QueueEventType.FLUSH;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, onFlush: onFlush, completer: completer));
    return completer.future;
  }

  /// deallocates queue resources (data already on the fs persists)
  Future<void> destroy() => _buffer.destroy();

  // buffer calls onData every time it's ready to process a new [_Event] and
  // then an event handler method gets executed according to [_Event.type]
  Future<void> _onData(QueueEvent event) async {
    if (event.type == QueueEventType.FLUSH) {
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
      await _write(event.item);      
      if (_len >= flushAt || _isExpired(_deadline)) await _onFlush(event);
      else event.completer.complete();
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  Future<void> _onFlush(QueueEvent event) async {
    try {
      // run optional flush action
      final OnFlush _onFlush = event.onFlush ?? onFlush;
      if (_onFlush != null) await _onFlush(await _toList());

      // clear on success
      await _onReset(event);

      // acknowledge
      event.completer.complete();
    } catch (e, s) {
      debugPrint('flush + ' + e.toString());
      event.completer.completeError(e, s);
    }
  }

  Future<void> _onReset(QueueEvent event) async {
    await _file((LocalStorage storage) async {
      await storage.clear(); // hard clear a bit slow!!
      _len = 0;
    });
  }

  Future<void> _onReload(QueueEvent event) async {
    await _file((LocalStorage storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem('$_len') == null) break;
      }
      if (_len > 0) _deadline = _newDeadline(flushTimeout);
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
      if (_len == 1) _deadline = _newDeadline(flushTimeout);
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
