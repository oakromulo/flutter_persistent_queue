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

import 'dart:async'
    show Completer, FutureOr, StreamController, StreamSubscription;
import 'package:localstorage/localstorage.dart' show LocalStorage;

/// A [PersistentQueue] stores data via [push] and clears it via [flush] calls.
class PersistentQueue {
  /// Constructs a new [PersistentQueue] or returns a previously cached one.
  ///
  /// [filename] gets instantiated under `ApplicationDocumentsDirectory` to
  /// store/load the persistent queue.
  ///
  /// An optional [onFlush] handler can be supplied at construction
  /// time, to be called implicitly before each [flush()] operation emptying
  /// the queue. When [onFlush] is provided the queue will be emptied as long
  /// as the handler does not return `false`.
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
      String nickname,
      FutureOr Function(List) onFlush}) {
    _configs[filename] = _Config(
        flushAt: flushAt,
        flushTimeout: flushTimeout,
        maxLength: maxLength ?? flushAt * 5,
        onFlush: onFlush);

    if (_queues.containsKey(filename)) {
      return _queues[filename];
    }

    return _queues[filename] =
        PersistentQueue._internal(filename, nickname ?? filename);
  }

  PersistentQueue._internal(this.filename, this.nickname)
      : _buffer = _Buffer() {
    _ready = _defer(_reload);
  }

  /// Permanent storage extensionless destination filename.
  final String filename;

  /// Optional queue name/alias for debug purposes, defaults to [filename].
  final String nickname;

  static final _configs = <String, _Config>{};
  static final _queues = <String, PersistentQueue>{};

  final _Buffer _buffer;

  DateTime _deadline;
  Exception _errorState;
  int _len = 0;
  Future<void> _ready;

  /// Actual queue length after buffered operations go through.
  Future<int> get length => _defer(() => _len);

  /// Flag indicating queue readiness after initial reload event.
  Future<void> get ready => _ready;

  /// Clear the list and return queued items.
  Future<void> clear() => _flushWrap(true);

  /// Dispose all queue resources.
  Future<void> destroy() => _buffer.defer(_destroy);

  /// Schedule a flush instruction to happen after current task buffer clears.
  ///
  /// An optional callback [onFlush] may be provided and the queue only gets
  /// emptied if [onFlush] does not return `false`. It holds priority over the
  /// also optional onFlush defined at construction time.
  Future<void> flush([FutureOr Function(List) onFlush]) =>
      _defer(() => _flush(onFlush));

  /// Push an [item] to the end of the [PersistentQueue] after buffer clears.
  ///
  /// p.s. [item] must be json encodable, as `json.encode()` is called over it
  Future<void> push(dynamic item) => _defer(() => _push(item));

  /// Preview a [List] of currently buffered items, without any dequeuing.
  Future<List> toList() => _flushWrap(false);

  _Config get _config => _configs[filename];
  bool get _isExpired => _deadline != null && _nowUtc.isAfter(_deadline);
  DateTime get _nowUtc => DateTime.now().toUtc();

  Future<T> _defer<T>(FutureOr<T> Function() action) {
    void checkErrorState() {
      if (_errorState != null) {
        throw Exception(_errorState);
      }
    }

    checkErrorState();

    return _buffer
        .defer<T>(() => Future.sync(checkErrorState).then((_) => action()));
  }

  Future<void> _destroy() {
    _configs.remove(filename);
    _queues.remove(filename);

    _errorState ??= Exception('Queue Destroyed');

    return _buffer.destroy();
  }

  Future<void> _file(Future<void> Function(LocalStorage) inputFunc) async {
    final storage = LocalStorage(filename);

    await storage.ready;
    await inputFunc(storage);
  }

  Future<void> _flush([FutureOr Function(List) onFlushParam]) async {
    final onFlush = onFlushParam ?? _config.onFlush ?? (_) => true;

    if (((await onFlush(await _toList())) ?? true) != false) {
      await _reset();
    }
  }

  Future<List> _flushWrap(bool shouldClear) {
    List list;

    return flush((_list) {
      list = _list;

      return shouldClear;
    }).then((_) => list);
  }

  Future<void> _push(dynamic item) async {
    if (_len > _config.maxLength) {
      throw Exception('QueueOverflow');
    }

    await _write(item);

    if ((_len >= _config.flushAt) || _isExpired) {
      await _flush();
    }
  }

  Future<void> _reload() async {
    try {
      _errorState = null;
      _len = 0;

      await _file((storage) async {
        while (await storage.getItem('$_len') != null) {
          ++_len;
        }
      });
    } catch (e) {
      _errorState = Exception(e.toString());
    }
  }

  Future<void> _reset() async {
    await _file((storage) async {
      await storage.clear();

      _len = 0;
    });
  }

  void _resetDeadline() => _deadline = _nowUtc.add(_config.flushTimeout);

  Future<List> _toList() async {
    if ((_len ?? 0) < 1) {
      return [];
    }

    final li = List(_len);

    await _file((storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem('$k');
      }
    });

    return li;
  }

  Future<void> _write(dynamic value) async {
    await _file((storage) async {
      await storage.setItem('$_len', value);

      if (++_len == 1) {
        _resetDeadline();
      }
    });
  }
}

class _Buffer {
  _Buffer() {
    _sub = _controller.stream.listen((action) => _sub.pause(action.run()));
  }

  final _controller = StreamController<_BufferItem>();
  StreamSubscription<_BufferItem> _sub;

  Future<T> defer<T>(FutureOr<T> Function() action) {
    final item = _BufferItem(action);

    _controller.add(item);

    return item.future;
  }

  Future<void> destroy() => _sub.cancel().then((_) => _controller.close());
}

class _BufferItem<T> {
  _BufferItem(this._handler);

  final _completer = Completer<T>();
  final FutureOr<T> Function() _handler;

  Future<T> get future => _completer.future;

  Future<T> run() async {
    try {
      final res = await Future.sync(_handler);

      _completer.complete(res);

      return res;
    } catch (e, s) {
      _completer.completeError(e, s);

      return null;
    }
  }
}

class _Config {
  _Config({this.flushAt, this.flushTimeout, this.maxLength, this.onFlush});

  final int flushAt;
  final Duration flushTimeout;
  final int maxLength;
  final FutureOr Function(List) onFlush;
}
