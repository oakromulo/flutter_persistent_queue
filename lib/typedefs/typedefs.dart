import 'package:localstorage/localstorage.dart' show LocalStorage;

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef OnFlush = Future<void> Function(List<Map<String, dynamic>>);

///
typedef OnError = void Function(dynamic error, [StackTrace stack]);

///
typedef OnReset = Future<void> Function();

/// @nodoc
typedef StorageFunc = Future<void> Function(LocalStorage);
