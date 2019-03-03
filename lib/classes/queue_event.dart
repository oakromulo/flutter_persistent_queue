/// @nodoc
// ignore_for_file: public_member_api_docs

import '../typedefs/typedefs.dart' show OnFlush, OnError;

class QueueEvent {
  QueueEvent(this.type, {this.item, this.onFlush, this.onError});
  final QueueEventType type;
  final Map<String, dynamic> item;
  final OnFlush onFlush;
  final OnError onError;
}

enum QueueEventType { FLUSH, PUSH, RELOAD, RESET }
