/// A simple file-based non-volatile persistent queue library for flutter.
///
/// Typical use-case scenario is for small to medium sized in-device buffers
/// storing persistent yet temporary mission-critical data, until it can be
/// efficiently and safely consumed / delivered permanently - such as for
/// custom analytics and specialized logging applications.
///
/// The current implementation is minimalist by design and only supports a
/// very minimal subset of methods. All methods calls are buffered and
/// executed sequentially on an isolated event loop per queue.
library flutter_persistent_queue;

import 'dart:async' show Completer;
import 'package:localstorage/localstorage.dart' show LocalStorage;
import './classes/queue_buffer.dart' show QueueBuffer;
import './classes/queue_event.dart' show QueueEvent, QueueEventType;
import './typedefs/typedefs.dart' show OnFlush, StorageFunc;

/// A basic implementation of persistent queues for flutter-compatible devices.
class PersistentQueue {
  /// Constructs a new [PersistentQueue] or loads a previously cached one.
  ///
  /// A [filename], not a `filepath`, is the only required parameter. It's used
  /// internally as a key for the persistent queue.
  ///
  /// The optional [filepath] is used to enforce a directory to store the queue
  /// named/keyed defined by [filename]. It defaults to the platform-specific
  /// application document directory.
  ///
  /// An optional [OnFlush] [onFlush] handler can be supplied at construction
  /// time, to be called implicitly before each [flush()] operation emptying
  /// the queue.
  ///
  /// The [flushAt] and [flushTimeout] parameters specify trigger conditions
  /// for firing automatic implicit [flush()] operations.
  ///
  /// [flushAt] establishes a desired target ceiling for locally store items,
  /// with a default of `100`. It's also possible to set a [flushTimeout]
  /// for a time-based [flush()] trigger, with a default [Duration] of 5
  /// minutes. Both parameters can only be bypassed by setting very large
  /// values, by design.
  ///
  /// Setting [maxLength] causes the queue to throw exceptions at [push] time
  /// when the queue internally holds more elements than this hard maximum. By
  /// default it's calculated as 5 times the size of [flushAt].
  ///
  /// The final [noPersist] optional named parameter allows the queue to be
  /// memory-only and not persist to permanent storage for testing purposes.
  factory PersistentQueue(String filename,
      {String filepath,
      OnFlush onFlush,
      int flushAt = 100,
      int maxLength,
      bool noPersist = false,
      Duration flushTimeout = const Duration(minutes: 5)}) {
    // return a previously cached PersistentQueue whenever a previous intance
    // existed under the same filename for the same execution run
    if (_cache.containsKey(filename)) {
      return _cache[filename];
    }

    // instantiate a new queue using internal implicit constructor
    final persistentQueue = PersistentQueue._internal(filename,
        filepath: filepath,
        onFlush: onFlush,
        flushAt: flushAt,
        flushTimeout: flushTimeout,
        maxLength: maxLength,
        noPersist: noPersist);

    // cache the recently instantiated queue
    _cache[filename] = persistentQueue;

    return persistentQueue;
  }

  // internal constructor called whenever a new queue is requested for a certain
  // [filename] not found on [_cache]
  PersistentQueue._internal(this.filename,
      {this.filepath,
      this.onFlush,
      this.flushAt,
      this.flushTimeout,
      int maxLength,
      bool noPersist})
      : _maxLength = maxLength ?? flushAt * 5 {
    // create a new event buffer
    _buffer = QueueBuffer<QueueEvent>(_onData);

    // specify realod/persist as the type for the first [QueueEvent]
    const type = QueueEventType.RELOAD;

    // set up a completer for the initial reload/persist event
    final completer = Completer<bool>();

    // set promise that indicates that queue is ready after initial reload event
    _ready = completer.future;

    // push the reload/persist event to the isolated buffer event so that
    // the queue can restore previously persisted data on permanent storage,
    // provided that it exists
    _buffer.push(QueueEvent(type, noPersist: noPersist, completer: completer));
  }

  /// Permanent storage extensionless destination filename.
  ///
  /// p.s. also used as caching key to avoid conflicting  re-instantiations.
  final String filename;

  /// Optional [String] to enforce a certain device path to store the queue.
  ///
  /// p.s. defaults to the platform-specific application document directory.
  final String filepath;

  /// Optional callback to be called before each implicit [flush] call.
  final OnFlush onFlush;

  /// Target number of queued elements that triggers an implicit [flush] call.
  final int flushAt;

  /// Target maximum time in queue before an implicit auto [flush] call.
  final Duration flushTimeout;

  // calculated or chosen max number of queued items, either in-memory or on fs
  final int _maxLength;

  // internal storage map for [PersistentQueue] instantiations
  static final _cache = <String, PersistentQueue>{};

  // internal buffer of [QueueEvents] to be consumed one by one
  QueueBuffer<QueueEvent> _buffer;

  // variable to hold eventual async exceptions and checked by
  // [_checkErrorState] whenever needed be before an action
  Exception _errorState;

  // promise indicating that queue is ready after initial reload event
  Future<bool> _ready;

  // maximum timestamp, defined at first insertion, before an implicit
  // auto-flush gets triggered
  DateTime _deadline;

  // internal counter of queued elements
  int _len = 0;

  /// the current number of elements in non-volatile storage
  int get length => _len;

  /// the current number of in-memory elements
  int get bufferLength => _buffer.length;

  /// Flag indicating queue readiness after initial reload event.
  Future<bool> get ready => _ready;

  /// Flag indicating actual queue length after buffered operations go through.
  Future<int> get futureLength {
    _checkErrorState();

    const type = QueueEventType.LENGTH;
    final completer = Completer<int>();
    _buffer.push(QueueEvent(type, completer: completer));

    return completer.future;
  }

  /// Push an [item] to the end of the [PersistentQueue] after buffer clears.
  Future<void> push(Map<String, dynamic> item) {
    _checkOverflow();
    _checkErrorState();

    const type = QueueEventType.PUSH;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, item: item, completer: completer));

    return completer.future;
  }

  /// Manually push a flush instruction to happen after current buffer clears.
  ///
  /// Optional handler callback [OnFlush] [onFlush] is called when it completes.
  Future<void> flush([OnFlush onFlush]) {
    _checkErrorState();

    const type = QueueEventType.FLUSH;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, onFlush: onFlush, completer: completer));

    return completer.future;
  }

  /// Return a list of currently buffered items
  Future<List<Map<String, dynamic>>> toList({bool growable = true}) {
    _checkErrorState();

    const type = QueueEventType.LIST;
    final completer = Completer<List<Map<String, dynamic>>>();
    _buffer.push(QueueEvent(type, growable: growable, completer: completer));

    return completer.future;
  }

  /// Optionally deallocate all queue resources when called
  Future<void> destroy({bool noPersist = false}) {
    const type = QueueEventType.DESTROY;
    final completer = Completer<void>();
    _buffer.push(QueueEvent(type, noPersist: noPersist, completer: completer));

    return completer.future;
  }

  // buffer calls onData every time it's ready to process a new [_Event] and
  // then an event handler method gets executed according to [_Event.type]
  Future<void> _onData(QueueEvent event) async {
    if (event.type == QueueEventType.FLUSH) {
      await _onFlush(event);
    } else if (event.type == QueueEventType.DESTROY) {
      await _onDestroy(event);
    } else if (event.type == QueueEventType.LENGTH) {
      _onLength(event);
    } else if (event.type == QueueEventType.LIST) {
      await _onList(event);
    } else if (event.type == QueueEventType.PUSH) {
      await _onPush(event);
    } else if (event.type == QueueEventType.RELOAD) {
      await _onReload(event);
    }
  }

  // internal handler called when a QueueEventType.PUSH gets dequeued
  Future<void> _onPush(QueueEvent event) async {
    try {
      await _write(event.item);

      if (_len >= flushAt || _expiredTimeout()) {
        await _onFlush(event);
      } else {
        event.completer.complete();
      }
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  // first event to be dequeued, scheduled once at construction-time
  Future<void> _onReload(QueueEvent event) async {
    try {
      _errorState = null;
      _len = 0;

      if (event.noPersist) {
        await _reset();
      } else {
        await _file((LocalStorage storage) async {
          while (await storage.getItem('$_len') != null) ++_len;
        });
      }

      event.completer.complete(true);
    } catch (e) {
      _errorState = Exception(e.toString());
      event.completer.complete(false);
    }
  }

  // internal handler called when a QueueEventType.LIST gets dequeued
  Future<void> _onList(QueueEvent event) async {
    try {
      List<Map<String, dynamic>> list = await _toList();

      if (event.growable) {
        list = List<Map<String, dynamic>>.from(list, growable: true);
      }

      event.completer.complete(list);
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  // internal handler called when a QueueEventType.FLUSH gets dequeued
  Future<void> _onFlush(QueueEvent event) async {
    try {
      // define optional flush action
      final OnFlush _onFlush = event.onFlush ?? onFlush;

      // run flush action if available/desired
      if (_onFlush != null) {
        await _onFlush(await _toList());
      }

      // clear on success
      await _reset();

      // acknowledge success
      event.completer.complete();
    } catch (e, s) {
      // acknowledge failure
      event.completer.completeError(e, s);
    }
  }

  // internal handler called when a QueueEventType.DESTROY gets dequeued
  Future<void> _onDestroy(QueueEvent event) async {
    try {
      // clear queued elements if not persisting
      if (event.noPersist) {
        await _reset();
      }

      // clear event buffer
      await _buffer.destroy();

      // remove current instance from object cache
      _cache.remove(filename);

      // set error state to avoid current instance to continue being used
      _errorState = Exception('Queue Destroyed');

      // acknowledge success
      event.completer.complete();
    } catch (e, s) {
      // acknowledge failure
      print(e.toString());
      event.completer.completeError(e, s);
    }
  }

  // internal handler called when a QueueEventType.LENGTH gets dequeued
  void _onLength(QueueEvent event) => event.completer.complete(_len);

  // should only be called by _onFlush, _onList, _onDestroy
  Future<List<Map<String, dynamic>>> _toList() async {
    // return empty array if no elements have been queued yet
    if (_len == null || _len < 1) {
      return [];
    }

    final li = List<Map<String, dynamic>>(_len);

    await _file((LocalStorage storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k') as Map<String, dynamic>;
      }
    });

    return li;
  }

  // helper clearing method called by _onDestroy, _onFlush, _onReload if needed
  Future<void> _reset() async {
    await _file((LocalStorage storage) async {
      await storage.clear(); // hard clear a bit slow!!
      _len = 0;
    });
  }

  // helper method to enqueue an element, called only by _onPush
  Future<void> _write(Map<String, dynamic> value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);

      if (++_len == 1) {
        _resetDeadline();
      }
    });
  }

  // LocalStorage wrapper to be called in isolation to avoid race conditions
  Future<void> _file(StorageFunc inputFunc) async {
    final storage = LocalStorage(filename, filepath);

    await storage.ready;
    await inputFunc(storage);
  }

  // helper method for throwing exceptions when queue is internally broken
  void _checkErrorState() {
    if (_errorState == null) {
      return;
    }

    throw Exception(_errorState);
  }

  // helper to calculate actual # of (written and to-be-written) queue items
  void _checkOverflow() {
    if (_len + _buffer.length - 1 <= _maxLength) {
      return;
    }

    throw Exception('QueueOverflow');
  }

  // util to set the flushTimeout deadline
  void _resetDeadline() => _deadline = _nowUtc().add(flushTimeout);

  // util to check if flushTimeout expired
  bool _expiredTimeout() => _deadline != null && _nowUtc().isAfter(_deadline);

  // util to get current utc datetime
  DateTime _nowUtc() => DateTime.now().toUtc();
}
