// ignore_for_file: public_member_api_docs

/// @nodoc
library queue_event;

import 'dart:async' show Completer;
import '../typedefs/typedefs.dart' show OnFlush;

/// @nodoc
class QueueEvent {
  QueueEvent(this.type,
      {this.completer, this.item, this.onFlush, this.growable, this.noPersist});
  final QueueEventType type;
  final Completer<dynamic> completer;
  final Map<String, dynamic> item;
  final OnFlush onFlush;
  final bool growable, noPersist;
}

/// @nodoc
enum QueueEventType { FLUSH, DESTROY, LENGTH, LIST, PUSH, RELOAD }
