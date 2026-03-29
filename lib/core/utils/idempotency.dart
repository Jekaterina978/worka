class IdempotencyGuard<T> {
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() action) {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = action();
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }
}
