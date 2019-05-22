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
import './typedefs/typedefs.dart' show OnFlush;

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
  /// the queue. When [onFlush] is provided the queue only flushes if the
  /// handler returns `true`.
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
  /// It's possible to force the instance being created to always replace any
  /// previously existing queues with the same [filename] on the global cache
  /// by setting the [noCache] parameter to `true`. In case a cache replacement
  /// happens then the old queue gets fully destroyed and dealloacted in favor
  /// of the new one.
  ///
  /// The final [noPersist] optional named parameter allows the queue to be
  /// memory-only. It will start empty without reloading from localstorage and
  /// will not persist to permanent storage. Mostly used for testing purposes.
  factory PersistentQueue(String filename,
      {String filepath,
      String alias,
      OnFlush onFlush,
      int flushAt = 100,
      int maxLength,
      bool noCache = false,
      bool noPersist = false,
      Duration flushTimeout = const Duration(minutes: 5)}) {
    if (_cache.containsKey(filename)) {
      if (!noCache) {
        return _cache[filename];
      }

      _cache[filename].destroy();
    }

    return _cache[filename] = PersistentQueue._internal(filename,
        filepath: filepath,
        alias: alias,
        onFlush: onFlush,
        flushAt: flushAt,
        flushTimeout: flushTimeout,
        maxLength: maxLength,
        noPersist: noPersist);
  }

  PersistentQueue._internal(this.filename,
      {this.filepath,
      this.alias,
      this.onFlush,
      this.flushAt,
      this.flushTimeout,
      int maxLength,
      bool noPersist})
      : _maxLength = maxLength ?? flushAt * 5 {
    _buffer = QueueBuffer<QueueEvent>(_onData);

    const type = QueueEventType.RELOAD;
    final completer = Completer<bool>();

    _ready = completer.future;

    _buffer.push(QueueEvent(type, noPersist: noPersist, completer: completer));
  }

  /// Permanent storage extensionless destination filename.
  ///
  /// p.s. also used as caching key to avoid conflicting  re-instantiations.
  final String filename;

  /// Queue nickname, fully optional.
  final String alias;

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

  // global <filename, queue> dictionary of all PersistentQueue instances
  static final _cache = <String, PersistentQueue>{};

  final int _maxLength;

  DateTime _deadline;
  Exception _errorState;
  Future<bool> _ready;
  QueueBuffer<QueueEvent> _buffer;

  // internal count of enqueued elements
  int _len = 0;

  /// Flag indicating queue readiness after initial reload event.
  Future<bool> get ready => _ready;

  /// Flag indicating actual queue length after buffered operations go through.
  Future<int> get length {
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

  /// Schedule a flush instruction to happen after current task buffer clears.
  ///
  /// An optional handler callback [OnFlush] [onFlush] may be provided so that
  /// the flush operation only clears out if it returns `true`. It holds
  /// priority over the [PersistentQueue.onFlush] handler defined at
  /// [PersistentQueue] construction time.
  Future<void> flush([OnFlush onFlush]) {
    _checkErrorState();

    const type = QueueEventType.FLUSH;
    final completer = Completer<void>();

    _buffer.push(QueueEvent(type, onFlush: onFlush, completer: completer));

    return completer.future;
  }

  /// Preview a [List] of currently buffered items, without any dequeuing.
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

  Future<void> _onReload(QueueEvent event) async {
    try {
      _errorState = null;
      _len = 0;

      if (event.noPersist) {
        await _reset();
      } else {
        await _file((LocalStorage storage) async {
          while (await storage.getItem('$_len') != null) {
            ++_len;
          }
        });
      }

      event.completer.complete(true);
    } catch (e) {
      _errorState = Exception(e.toString());
      event.completer.complete(false);
    }
  }

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

  Future<void> _onFlush(QueueEvent event) async {
    try {
      final OnFlush _flushFunc = event.onFlush ?? onFlush ?? (_) async => true;

      final bool flushSuccess = (await _flushFunc(await _toList())) ?? false;

      if (flushSuccess) {
        await _reset();
      }

      event.completer.complete();
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  Future<void> _onDestroy(QueueEvent event) async {
    try {
      if (event.noPersist) {
        await _reset();
      }

      // clear event buffer and remove destroyed instance from cache
      await _buffer.destroy();
      _cache.remove(filename);

      // set error state to disallow further operations on leftover instance
      _errorState = Exception('Queue Destroyed');

      event.completer.complete();
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  void _onLength(QueueEvent event) => event.completer.complete(_len);

  Future<List<Map<String, dynamic>>> _toList() async {
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

  Future<void> _reset() async {
    await _file((LocalStorage storage) async {
      await storage.clear();

      _len = 0;
    });
  }

  Future<void> _write(Map<String, dynamic> value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);

      if (++_len == 1) {
        _resetDeadline();
      }
    });
  }

  Future<void> _file(_StorageFunc inputFunc) async {
    final storage = LocalStorage(filename, filepath);

    await storage.ready;
    await inputFunc(storage);
  }

  void _checkErrorState() {
    if (_errorState == null) {
      return;
    }

    throw Exception(_errorState);
  }

  void _checkOverflow() {
    if (_len + _buffer.length - 1 <= _maxLength) {
      return;
    }

    throw Exception('QueueOverflow');
  }

  void _resetDeadline() => _deadline = _nowUtc().add(flushTimeout);
  bool _expiredTimeout() => _deadline != null && _nowUtc().isAfter(_deadline);

  DateTime _nowUtc() => DateTime.now().toUtc();
}

typedef _StorageFunc = Future<void> Function(LocalStorage);
