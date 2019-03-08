///
library flutter_persistent_queue;

import 'dart:async' show Completer;

import 'package:localstorage/localstorage.dart' show LocalStorage;

import './classes/queue_buffer.dart' show QueueBuffer;
import './classes/queue_event.dart' show QueueEvent, QueueEventType;
import './typedefs/typedefs.dart' show OnFlush, StorageFunc;

///
class PersistentQueue {
  ///
  factory PersistentQueue(String filename,
      {OnFlush onFlush, int flushAt, int maxLength}) {
    if (_cache.containsKey(filename)) return _cache[filename];

    final persistentQueue = PersistentQueue._internal(filename,
        onFlush: onFlush,
        flushAt: flushAt,
        //flushTimeout: flushTimeout,
        maxLength: maxLength);
    _cache[filename] = persistentQueue;
    return persistentQueue;
  }

  PersistentQueue._internal(this.filename,
      {this.onFlush,
      this.flushAt = 100,
      //this.flushTimeout = const Duration(minutes: 5),
      int maxLength})
      : _maxLength = maxLength ?? flushAt * 5 {
    final completer = Completer<bool>();
    _ready = completer.future;
    _buffer = QueueBuffer<QueueEvent>(_onData);
    _buffer.push(QueueEvent(QueueEventType.RELOAD, completer: completer));
  }

  ///
  final String filename;

  ///
  final OnFlush onFlush;

  ///
  final int flushAt;

  ///
  //final Duration flushTimeout;

  // max number of queued items, either in-memory or on fs
  final int _maxLength;

  static final _cache = <String, PersistentQueue>{};

  QueueBuffer<QueueEvent> _buffer;
  Future<bool> _ready;
  String _reloadError;
  //DateTime _deadline;
  int _len = 0;

  /// the current number of elements in non-volatile storage
  int get length => _len;

  /// the current number of in-memory elements
  int get bufferLength => _buffer.length;

  ///
  Future<bool> get ready => _ready;

  ///
  Future<void> push(Map<String, dynamic> item) {
    _checkOverflow();
    _checkReloadError();
    const type = QueueEventType.PUSH;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, item: item, completer: completer));
    return completer.future;
  }

  /// push a flush instruction to the end of the event buffer
  Future<void> flush([OnFlush onFlush]) {
    _checkReloadError();
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
    }
  }

  Future<void> _onPush(QueueEvent event) async {
    try {
      await _write(event.item);
      if (_len >= flushAt /*|| _isExpired(_deadline)*/) {
        await _onFlush(event);
      } else {
        event.completer.complete();
      }
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  // should only be scheduled once at construction-time, first event to run
  Future<void> _onReload(QueueEvent event) async {
    try {
      _reloadError = null;
      await _file((LocalStorage storage) async {
        for (_len = 0; await storage.getItem('$_len') != null; ++_len);
      });
      event.completer.complete(true);
    } catch (e) {
      _reloadError = e.toString();
      event.completer.complete(false);
    }
  }

  Future<void> _onFlush(QueueEvent event) async {
    try {
      // run optional flush action
      final OnFlush _onFlush = event.onFlush ?? onFlush;
      if (_onFlush != null) await _onFlush(await _toList());

      // clear on success
      await _reset(event);

      // acknowledge
      event.completer.complete();
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  // should only be called by _onFlush
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

  // should only be called by _onFlush
  Future<void> _reset(QueueEvent event) async {
    await _file((LocalStorage storage) async {
      await storage.clear(); // hard clear a bit slow!!
      _len = 0;
    });
  }

  // should only be called by _onPush
  Future<void> _write(Map<String, dynamic> value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);
      _len++;
      //if (_len == 1) _deadline = _newDeadline(flushTimeout);
    });
  }

  Future<void> _file(StorageFunc inputFunc) async {
    final storage = LocalStorage(filename);
    await storage.ready;
    await inputFunc(storage);
  }

  void _checkReloadError() {
    if (_reloadError == null) return;
    throw Exception(_reloadError);
  }

  void _checkOverflow() {
    if (_len + _buffer.length <= _maxLength) return;
    throw Exception('QueueOverflow');
  }

  //DateTime _newDeadline(Duration flushTimeout) => _nowUtc().add(flushTimeout);
  //bool _isExpired(DateTime deadline) => _nowUtc().isAfter(deadline);
  //DateTime _nowUtc() => DateTime.now().toUtc();
}
