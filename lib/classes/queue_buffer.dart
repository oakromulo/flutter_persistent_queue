// ignore_for_file: public_member_api_docs
import 'dart:async';

/// @nodoc
class QueueBuffer<T> {
  QueueBuffer(Future<void> Function(T) onData) {
    _sub = _controller.stream.listen((T event) {
      _sub.pause(onData(event).whenComplete(() => _len--));
    });
  }

  final _controller = StreamController<T>();
  StreamSubscription<T> _sub;
  int _len = 0;

  int get length => _len;

  void push(T event) {
    _len++;
    _controller.add(event);
  }

  Future<void> destroy() async {
    await _sub.cancel();
    await _controller.close();
  }
}
