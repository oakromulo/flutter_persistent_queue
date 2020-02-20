/// A file-based queue that persists on local storage for flutter mobile apps.
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

import 'dart:async' show FutureOr;
import 'package:localstorage/localstorage.dart' show LocalStorage;
import './queue_buffer.dart' show QueueBuffer;

/// A [PersistentQueue] stores data via [push] and clears it via [flush] calls.
class PersistentQueue {
  /// Constructs a new [PersistentQueue] or returns a previously cached one.
  ///
  /// [filename] gets instantiated under `ApplicationDocumentsDirectory` to
  /// store/load the persistent queue.
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
  factory PersistentQueue(String filename,
      {int flushAt = 100,
      Duration flushTimeout = const Duration(minutes: 5),
      int maxLength,
      OnFlush onFlush}) {
    _configs[filename] = _QConfig(
        flushAt: flushAt,
        flushTimeout: flushTimeout,
        maxLength: maxLength ?? flushAt * 5,
        onFlush: onFlush);

    if (_cache.containsKey(filename)) {
      return _cache[filename];
    }

    return _cache[filename] = PersistentQueue._internal(filename);
  }

  PersistentQueue._internal(this.filename) : _buffer = QueueBuffer() {
    _ready = _buffer.defer<void>(_reload);
  }

  /// Permanent storage extensionless destination filename.
  final String filename;

  static final _cache = <String, PersistentQueue>{};
  static final _configs = <String, _QConfig>{};

  final QueueBuffer _buffer;

  DateTime _deadline;
  Exception _errorState;
  int _len = 0;
  Future<void> _ready;

  /// Actual queue length after buffered operations go through.
  Future<int> get length {
    _checkErrorState();

    return _buffer.defer<int>(() => _len);
  }

  /// Flag indicating queue readiness after initial reload event.
  Future<void> get ready => _ready;

  /// Dispose all queue resources.
  Future<void> destroy() => _buffer.defer(_destroy);

  /// Schedule a flush instruction to happen after current task buffer clears.
  ///
  /// An optional handler callback [OnFlush] [onFlush] may be provided so that
  /// the flush operation only clears out if it returns `true`. It holds
  /// priority over the [onFlush] handler defined at construction time.
  Future<void> flush([OnFlush onFlush]) {
    _checkErrorState();

    return _buffer.defer(() => _flush(onFlush));
  }

  /// Push an [item] to the end of the [PersistentQueue] after buffer clears.
  ///
  /// p.s. [item] must be json encodable, as `json.encode()` is called over it
  Future<void> push(dynamic item) {
    _checkOverflow();
    _checkErrorState();

    return _buffer.defer(() => _push(item));
  }

  /// Preview a [List] of currently buffered items, without any dequeuing.
  Future<List<dynamic>> toList() {
    _checkErrorState();

    return _buffer.defer<List<dynamic>>(_toList);
  }

  bool get _isExpired => _deadline != null && _nowUtc.isAfter(_deadline);
  DateTime get _nowUtc => DateTime.now().toUtc();

  void _checkErrorState() {
    if (_errorState == null) {
      return;
    }

    throw Exception(_errorState);
  }

  void _checkOverflow() {
    if (_len + _buffer.length - 1 <= _configs[filename].maxLength) {
      return;
    }

    throw Exception('QueueOverflow');
  }

  Future<void> _destroy() async {
    await _buffer.destroy();

    _cache.remove(filename);
    _errorState = Exception('Queue Destroyed');
  }

  Future<void> _file(_StorageFunc inputFunc) async {
    final storage = LocalStorage(filename);

    await storage.ready;
    await inputFunc(storage);
  }

  Future<void> _flush([OnFlush onFlushParam]) async {
    final OnFlush _flushFunc =
        onFlushParam ?? _configs[filename].onFlush ?? (_) => true;

    final bool flushSuccess = (await _flushFunc(await _toList())) ?? false;

    if (flushSuccess) {
      await _reset();
    }
  }

  Future<void> _push(dynamic item) async {
    await _write(item);

    if (_len >= _configs[filename].flushAt || _isExpired) {
      await _flush();
    }
  }

  Future<void> _reload() async {
    try {
      _errorState = null;
      _len = 0;

      await _file((LocalStorage storage) async {
        while (await storage.getItem('$_len') != null) {
          ++_len;
        }
      });
    } catch (e) {
      print(e);
      _errorState = Exception(e.toString());
    }
  }

  Future<void> _reset() async {
    await _file((LocalStorage storage) async {
      await storage.clear();

      _len = 0;
    });
  }

  void _resetDeadline() =>
      _deadline = _nowUtc.add(_configs[filename].flushTimeout);

  Future<List<dynamic>> _toList() async {
    if (_len == null || _len < 1) {
      return <dynamic>[];
    }

    final li = List<dynamic>(_len);

    await _file((LocalStorage storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k');
      }
    });

    return li;
  }

  Future<void> _write(dynamic value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);

      if (++_len == 1) {
        _resetDeadline();
      }
    });
  }
}

class _QConfig {
  _QConfig({this.flushAt, this.flushTimeout, this.maxLength, this.onFlush});

  final int flushAt;
  final Duration flushTimeout;
  final int maxLength;
  final OnFlush onFlush;
}

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef OnFlush = FutureOr<bool> Function(List<dynamic>);

typedef _StorageFunc = Future<void> Function(LocalStorage);
