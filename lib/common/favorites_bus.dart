import 'dart:async';

class FavoritesBus {
  static final StreamController<void> _c = StreamController<void>.broadcast();

  static Stream<void> get stream => _c.stream;

  static void notify() {
    if (!_c.isClosed) _c.add(null);
  }

  static void dispose() {
    _c.close();
  }
}