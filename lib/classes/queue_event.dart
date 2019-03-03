/// @nodoc
// ignore_for_file: public_member_api_docs

import '../typedefs/typedefs.dart' show AsyncFlushFunc, ErrFunc;

class QueueEvent {
  QueueEvent(this.type, {this.item, this.flush, this.onError});
  final QueueEventType type;
  final Map<String, dynamic> item;
  final AsyncFlushFunc flush;
  final ErrFunc onError;
}

enum QueueEventType { FLUSH, PUSH, RELOAD, RESET }