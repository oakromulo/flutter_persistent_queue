/// A file-based queue package lib for flutter.
///
/// The current implementation is minimalist by design and only supports a very
/// minimal subset of methods for the time being. It's built on top of
/// [Localstorage](https://github.com/lesnitsky/flutter_localstorage). The main
/// focus is to provide functionality for small yet fast disk-based queues (less
/// than ~10k JSON encodable items).
///
/// p.s. not a [`dart:collection`](
/// https://pub.dartlang.org/documentation/collection/latest/)
library flutter_persistent_queue;

import 'package:meta/meta.dart';
import 'package:localstorage/localstorage.dart';
import 'package:synchronized/synchronized.dart';

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef AsyncFlushFunc = Future<void> Function(List<Map<String, dynamic>>);

typedef _StorageFunc = Future<void> Function(LocalStorage);
typedef _VoidAsyncFunc = Future<void> Function();

/// A basic implementation of persistent queues for flutter-compatible devices.
///
/// It works by naïvely enqueuing each JSON-encodabled item to its own
/// non-volatile file on the supported devices. It's not suitable for very long
/// queues that could e.g. easily overrun the strict maximum number of opened
/// files on `iOS`. This particular design choice limits potential use cases but
/// provides high performance within a very low resource footprint, as it does
/// not require the time-consuming and resource-intensive serialization and
/// deserialization of potentially large
/// [`dart:collections`](
/// https://pub.dartlang.org/documentation/collection/latest/) of JSON maps.
///
/// p.s. this class was originally designed as an utility for buffering
/// analytics events and their respective [Map<String, dynamic>] JSON payloads.
class PersistentQueue {
  /// Creates a new [PersistentQueue], to be used after [PersistentQueue.setup].
  ///
  /// A [filename], not a `filepath`, is the only required parameter. The actual
  /// storage destination is currently undefined and platform-specific, as per
  /// this [issue](
  /// https://github.com/lesnitsky/flutter_localstorage/issues/4).
  ///
  /// An optional [AsyncFlushFunc] [flushFunc] can be supplied at construction
  /// time, to be called before each [flush()] operation emptying the queue.
  ///
  /// The next two named parameters [flushAt] and [flushTimeout] specify
  /// trigger conditions for firing automatic implicit [flush()] operations.
  /// [flushAt] establishes the target cap (not a maximum!) for locally stored
  /// items, with a default of `100`. It's also possible to set a [flushTimeout]
  /// for a time-based [flush()] trigger, with a default [Duration] of 5
  /// minutes. Both parameters can only be bypassed by setting very large
  /// values, by design.
  PersistentQueue(
      {@required String filename,
      AsyncFlushFunc flushFunc,
      int flushAt = 100,
      Duration flushTimeout = const Duration(minutes: 5)})
      : _filename = filename,
        _flushFunc = flushFunc,
        _flushAt = flushAt,
        _flushTimeout = flushTimeout;

  final String _filename;
  final AsyncFlushFunc _flushFunc;
  final int _flushAt;
  final Duration _flushTimeout;
  final _queueLock = Lock(reentrant: true), _fileLock = Lock(reentrant: true);

  int _len;
  DateTime _deadline;
  bool _ready = false;

  /// The current number of queued elements.
  int get length => _len;

  /// The current queue status, indicating readiness for [push()].
  ///
  /// It returns `false` until [setup()] gets completed successfully. Trying to
  /// write items before the queue is ready causes a `PersistQueueNotReady`
  /// [Exception] to be thrown.
  bool get ready => _ready;

  /// Restores previously queued elements, if available, from the filesystem.
  ///
  /// A queue only gets [ready] for write operations after a [setup()] finishes
  /// succesfully after construction. Failing to do so yields a
  /// `PersistQueueNotReady` [Exception].
  Future<void> setup() async {
    _ready = false;
    await _reload();
    _ready = true;
  }

  /// Flushes the queue, optionally running an async [flushFunc] over all queued
  /// elements before they get permanently cleared.
  ///
  /// p.s if an [AsyncFlushFunc] was previously provided at construction time
  /// and the optional [flushFunc] argument is also given then the latter gets
  /// prioritized and called instead.
  Future<void> flush([AsyncFlushFunc flushFunc]) async {
    await _queueIdle(() async {
      final _asyncFlushFunc = flushFunc ?? _flushFunc;
      if (_asyncFlushFunc != null) await _asyncFlushFunc(await _toList());
      await _reset();
    });
  }

  /// Pushes a JSON encodable [item] to the end of the queue.
  Future<void> push(Map<String, dynamic> item) async {
    await _queueIdle(() async {
      await _write(item);
      if (_len == 1) _newDeadline();
      if (_len >= _flushAt || _deadlineExpired()) await flush();
    });
  }

  Future<void> _queueIdle(_VoidAsyncFunc inputFunc) async {
    if (!_ready) throw Exception('PersistQueueNotReady');
    await _queueLock.synchronized(() async {
      await inputFunc();
    });
  }

  Future<List<Map<String, dynamic>>> _toList() async {
    final List<Map<String, dynamic>> li = List(_len);
    await _fileIdle((storage) async {
      for (int k = 0; k < _len; ++k) {
        li[k] = await storage.getItem(k.toString()) as Map<String, dynamic>;
      }
    });
    return li;
  }

  Future<void> _write(Map<String, dynamic> value) async {
    await _fileIdle((storage) async {
      await storage.setItem(_len.toString(), value);
      _len++;
    });
  }

  Future<void> _reload() async {
    await _fileIdle((storage) async {
      for (_len = 0;; ++_len) {
        if (await storage.getItem(_len.toString()) == null) break;
      }
      if (_len > 0) _newDeadline();
    });
  }

  Future<void> _reset() async {
    await _fileIdle((storage) async {
      await storage.clear();
      _len = 0;
    });
  }

  Future<void> _fileIdle(_StorageFunc inputFunc) async {
    await _fileLock.synchronized(() async {
      final storage = LocalStorage(_filename);
      await storage.ready;
      await inputFunc(storage);
    });
  }

  void _newDeadline() => _deadline = DateTime.now().toUtc().add(_flushTimeout);
  bool _deadlineExpired() => DateTime.now().toUtc().isAfter(_deadline);
}
