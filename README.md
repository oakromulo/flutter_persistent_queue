# persistent_queue

Simple file-based non-volatile queue library for flutter.

Typical use-case scenario is for small to medium sized in-device buffers
storing persistent yet temporary mission-critical data, until it can be
efficiently and safely consumed / delivered permanently - such as for
custom analytics and specialized logging applications.

## Installation

Add dependency to `pubspec.yaml`:

```yaml
dependencies:
  ...
  flutter_persistent_queue: ^6.0.3
```

Run in your terminal:

```sh
flutter packages get
```

## Example

```dart
import 'package:flutter_persistent_queue/flutter_persistent_queue.dart';

// instantiate a new queue `pq`, with auto-flush set at 10 items
final pq = PersistentQueue('pq', flushAt: 10, onFlush: (list) async {
  print('auto-flush\n$list');
});

// push 25 Map<<String, dynamic>> items (await is optional)
for (int i = 0; i < 25; ++i) {
  pq.push(<String, dynamic>{'i': i});
}

// trigger a final manual flush for the remaining items
pq.flush((list) async => print('manual-flush\n$list'));

// check if all items have been flushed
assert(await pq.futureLength == 0);

// deallocate resources, if needed
await pq.destroy();
```

## Testing

For integration / performance tests:

```sh
git clone https://github.com/oakromulo/flutter_persistent_queue.git
cd ~/flutter_persistent_queue/test
flutter drive --target=test_driver/app.dart
```

## Building documentation files

```sh
rm -rf doc
dartdoc --exclude 'dart:async,dart:collection,dart:convert,dart:core,dart:developer,dart:io,dart:isolate,dart:math,dart:typed_data,dart:ui'
```

## How it works

Each JSON-encodable item when enqueued goes to its own indexed key in a single
non-volatile file (one file per uniquely named queue) to an unspecified location
on the permanent storage of a flutter-compatible device.

This particular design choice limits potential use cases requiring very long
queues but otherwise provides good performance within a limited resource
footprint, as it doesn't require serializing and deserializing
contiguous or chunked [`dart:collections`](https://pub.dartlang.org/documentation/collection/latest/) to the filesystem.

Every `push()` call triggers an asynchronous and isolated write to the
permanent storage. If the caller awaits until its completion, it is notified
via [Completers](api.dartlang.org/stable/2.2.0/dart-async/Completer-class.html)
and afterwards there's no possibility of data loss from the application
perspective.

After user-defined `flush()` operations (either manual or auto-triggered) the
queue is fully emptied if and only if the user-defined `onFlush` does not throw
any errors.

All PersistentQueue methods are consumed sequentially (according to the strict
chronological order of its calls) one at a time on a dedicated
producer / consumer event loop.

Performance of persisted queues on standard simulated devices must be of at
least 500 writes/second. This constraint is verified on integration tests.

All filesystem and JSON operations are abstracted by the minimalistic
[flutter_localstorage](https://github.com/lesnitsky/flutter_localstorage)
library.

## License

MIT
