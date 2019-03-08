/// @nodoc
// ignore_for_file: public_member_api_docs

import 'dart:async' show Completer;
import '../typedefs/typedefs.dart' show OnFlush;

class QueueEvent {
  QueueEvent(this.type, {this.completer, this.item, this.onFlush});
  final QueueEventType type;
  final Completer<dynamic> completer;
  final Map<String, dynamic> item;
  final OnFlush onFlush;
}

enum QueueEventType { FLUSH, LENGTH, PUSH, RELOAD }
