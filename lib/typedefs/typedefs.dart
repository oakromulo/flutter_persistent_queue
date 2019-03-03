import 'package:localstorage/localstorage.dart' show LocalStorage;

/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef AsyncFlushFunc = Future<void> Function(List<Map<String, dynamic>>);

///
typedef ErrFunc = Function(dynamic error, [StackTrace stack]);

/// @nodoc
typedef StorageFunc = Future<void> Function(LocalStorage);
