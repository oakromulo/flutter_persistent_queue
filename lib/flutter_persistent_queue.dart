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

import 'dart:async' show Completer;

import 'package:localstorage/localstorage.dart' show LocalStorage;

import './classes/queue_buffer.dart' show QueueBuffer;
import './classes/queue_event.dart' show QueueEvent, QueueEventType;
import './typedefs/typedefs.dart' show OnFlush;

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

  PersistentQueue._internal(this.filename) {
    _buffer = QueueBuffer<QueueEvent>(_onEvent);

    const type = QueueEventType.RELOAD;
    final completer = Completer<bool>();

    _ready = completer.future;

    _buffer.push(QueueEvent(type, completer: completer));
  }

  /// Permanent storage extensionless destination filename.
  final String filename;

  static final _cache = <String, PersistentQueue>{};
  static final _configs = <String, _QConfig>{};

  DateTime _deadline;
  Exception _errorState;
  int _len = 0;
  Future<bool> _ready;
  QueueBuffer<QueueEvent> _buffer;

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

  /// Target number of queued elements that triggers an implicit [flush].
  int get flushAt => _configs[filename].flushAt;

  /// Target maximum time in queue before an implicit auto [flush].
  Duration get flushTimeout => _configs[filename].flushTimeout;

  /// Queue throws exceptions at [push] time if already at [maxLength] elements.
  int get maxLength => _configs[filename].maxLength;

  /// Optional callback to be implicitly called on each internal [flush].
  OnFlush get onFlush => _configs[filename].onFlush;

  /// Push an [item] to the end of the [PersistentQueue] after buffer clears.
  ///
  /// p.s. [item] must be json encodable, as `json.encode()` is called over it
  Future<void> push(dynamic item) {
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
  /// priority over the [onFlush] handler defined at construction time.
  Future<void> flush([OnFlush onFlush]) {
    _checkErrorState();

    const type = QueueEventType.FLUSH;
    final completer = Completer<void>();

    _buffer.push(QueueEvent(type, onFlush: onFlush, completer: completer));

    return completer.future;
  }

  /// Preview a [List] of currently buffered items, without any dequeuing.
  Future<List<dynamic>> toList() {
    _checkErrorState();

    const type = QueueEventType.LIST;
    final completer = Completer<List<dynamic>>();

    _buffer.push(QueueEvent(type, completer: completer));

    return completer.future;
  }

  /// Optionally deallocate all queue resources when called
  Future<void> destroy({bool noPersist = false}) {
    const type = QueueEventType.DESTROY;
    final completer = Completer<void>();

    _buffer.push(QueueEvent(type, completer: completer));

    return completer.future;
  }

  Future<void> _onEvent(QueueEvent event) async {
    if (event.type == QueueEventType.FLUSH) {
      await _onFlushEvent(event);
    } else if (event.type == QueueEventType.DESTROY) {
      await _onDestroyEvent(event);
    } else if (event.type == QueueEventType.LENGTH) {
      _onLengthEvent(event);
    } else if (event.type == QueueEventType.LIST) {
      await _onListEvent(event);
    } else if (event.type == QueueEventType.PUSH) {
      await _onPushEvent(event);
    } else if (event.type == QueueEventType.RELOAD) {
      await _onReloadEvent(event);
    }
  }

  Future<void> _onPushEvent(QueueEvent event) async {
    try {
      await _write(event.item);

      if (_len >= flushAt || _expiredTimeout()) {
        await _onFlushEvent(event);
      } else {
        event.completer.complete();
      }
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  Future<void> _onReloadEvent(QueueEvent event) async {
    try {
      _errorState = null;
      _len = 0;

      await _file((LocalStorage storage) async {
        while (await storage.getItem('$_len') != null) {
          ++_len;
        }
      });

      event.completer.complete(true);
    } catch (e) {
      _errorState = Exception(e.toString());
      event.completer.complete(false);
    }
  }

  Future<void> _onListEvent(QueueEvent event) async {
    try {
      event.completer.complete(await _toList());
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  Future<void> _onFlushEvent(QueueEvent event) async {
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

  Future<void> _onDestroyEvent(QueueEvent event) async {
    try {
      await _buffer.destroy();
      _cache.remove(filename);

      _errorState = Exception('Queue Destroyed');

      event.completer.complete();
    } catch (e, s) {
      event.completer.completeError(e, s);
    }
  }

  void _onLengthEvent(QueueEvent event) => event.completer.complete(_len);

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

  Future<void> _reset() async {
    await _file((LocalStorage storage) async {
      await storage.clear();

      _len = 0;
    });
  }

  Future<void> _write(dynamic value) async {
    await _file((LocalStorage storage) async {
      await storage.setItem('$_len', value);

      if (++_len == 1) {
        _resetDeadline();
      }
    });
  }

  Future<void> _file(_StorageFunc inputFunc) async {
    final storage = LocalStorage(filename);

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
    if (_len + _buffer.length - 1 <= maxLength) {
      return;
    }

    throw Exception('QueueOverflow');
  }

  void _resetDeadline() => _deadline = _nowUtc().add(flushTimeout);
  bool _expiredTimeout() => _deadline != null && _nowUtc().isAfter(_deadline);

  DateTime _nowUtc() => DateTime.now().toUtc();
}

class _QConfig {
  _QConfig({this.flushAt, this.flushTimeout, this.maxLength, this.onFlush});

  final int flushAt;
  final Duration flushTimeout;
  final int maxLength;
  final OnFlush onFlush;
}

typedef _StorageFunc = Future<void> Function(LocalStorage);
