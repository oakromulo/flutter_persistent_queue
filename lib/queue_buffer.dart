/// @nodoc
library queue_buffer;

import 'dart:async'
    show Completer, FutureOr, StreamController, StreamSubscription;

/// @nodoc
class QueueBuffer {
  /// @nodoc
  QueueBuffer() {
    _subscription = _controller.stream.listen(_onData);
  }

  final _controller = StreamController<QueueEvent>();
  StreamSubscription<QueueEvent> _subscription;

  int _len = 0;

  /// @nodoc
  int get length => _len;

  /// @nodoc
  Future<T> defer<T>(FutureOr<T> Function() function) async {
    final event = QueueEvent(function);

    _controller.add(event);
    _len++;

    return await event.future as T;
  }

  /// @nodoc
  Future<void> destroy() async {
    await _subscription.cancel();
    await _controller.close();
  }

  void _onData(QueueEvent event) =>
      _subscription.pause(event.run().whenComplete(() => _len--));
}

/// @nodoc
class QueueEvent {
  /// @nodoc
  QueueEvent(this._handler);

  final _completer = Completer<dynamic>();
  final FutureOr<dynamic> Function() _handler;

  /// @nodoc
  Future<dynamic> get future => _completer.future;

  /// @nodoc
  Future<dynamic> run() async {
    try {
      final dynamic res = await Future<dynamic>.sync(_handler);

      _completer.complete(res);

      return res;
    } catch (e, s) {
      _completer.completeError(e, s);

      return null;
    }
  }
}
