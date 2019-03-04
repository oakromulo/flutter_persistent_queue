import 'package:localstorage/localstorage.dart' show LocalStorage;

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef OnFlush = Future<void> Function(List<Map<String, dynamic>>);

/// @nodoc
typedef StorageFunc = Future<void> Function(LocalStorage);
