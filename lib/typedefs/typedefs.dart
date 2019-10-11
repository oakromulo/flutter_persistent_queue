/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef OnFlush = Future<bool> Function(List<dynamic>);
