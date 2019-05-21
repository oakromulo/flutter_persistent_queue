/// A spec for optional queue iteration prior to a [PersistentQueue.flush()].
typedef OnFlush = Future<void> Function(List<Map<String, dynamic>>);
