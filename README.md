# persistent_queue

Simple file-based non-volatile queue library for flutter.


## Installation

Add dependency to `pubspec.yaml`:

```yaml
dependencies:
  ...
  flutter_persistent_queue: ^0.1.2
```

Run in your terminal:

```sh
flutter packages get
```
<!--
## Example

```dart

```
-->

## How it works

Each JSON-encodable item to be queued goes to its own non-volatile file on the
flutter-compatible devices. This particular design choice limits potential use
cases requiring very long queues but otherwise provides high performance with
very reduced resource usage, as it doesn't require serializing and deserializing
contiguous or chunked [`dart:collections`](
https://pub.dartlang.org/documentation/collection/latest/) to the filesystem.

It's built on top of the also minimalistic [Localstorage](
https://github.com/lesnitsky/flutter_localstorage) library. Concurrency-safety
and sequential correctness is provided by the fantastic and easy to use
[Synchronized](https://github.com/tekartik/synchronized.dart) reentrant locks.


## License

MIT
