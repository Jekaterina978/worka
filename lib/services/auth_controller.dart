import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

typedef AuthResetCallback = void Function();

class AuthController {
  AuthController._();

  static final AuthController instance = AuthController._();

  final ValueNotifier<String?> uidListenable = ValueNotifier<String?>(null);
  final StreamController<String?> _uidStreamController =
      StreamController<String?>.broadcast();
  final Map<String, AuthResetCallback> _resetters =
      <String, AuthResetCallback>{};

  StreamSubscription<User?>? _authSub;
  Timer? _nullDebounce;
  String? _currentUid;
  static const Duration _kNullAuthDebounce = Duration(milliseconds: 800);

  String? get currentUid => _currentUid;
  Stream<String?> get uidStream => _uidStreamController.stream;

  void init() {
    if (_authSub != null) return;
    _currentUid = FirebaseAuth.instance.currentUser?.uid.trim();
    uidListenable.value = _currentUid;
    _uidStreamController.add(_currentUid);

    _authSub = FirebaseAuth.instance.authStateChanges().listen(_handleAuth);
  }

  void registerResetter(String key, AuthResetCallback callback) {
    _resetters[key] = callback;
  }

  void unregisterResetter(String key) {
    _resetters.remove(key);
  }

  void _handleAuth(User? user) {
    final nextUid = user?.uid.trim();
    if (nextUid == null && (_currentUid?.isNotEmpty ?? false)) {
      _nullDebounce?.cancel();
      _nullDebounce = Timer(_kNullAuthDebounce, () {
        if (FirebaseAuth.instance.currentUser != null) return;
        _applyUidChange(null);
      });
      if (kDebugMode) {
        debugPrint(
          'AuthController observed transient null auth, waiting before resets',
        );
      }
      return;
    }

    _nullDebounce?.cancel();
    _applyUidChange(nextUid);
  }

  void _applyUidChange(String? nextUid) {
    if (nextUid == _currentUid) return;

    final prevUid = _currentUid;
    _currentUid = nextUid;

    if (kDebugMode) {
      debugPrint(
        'Auth uid changed ${prevUid ?? "<guest>"} -> ${nextUid ?? "<guest>"}',
      );
    }

    for (final entry in _resetters.entries) {
      try {
        entry.value();
        if (kDebugMode) {
          debugPrint('AuthController resetter "${entry.key}" executed');
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AuthController resetter "${entry.key}" failed: $e');
          debugPrint('$st');
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Auth uid changed ${prevUid ?? "<guest>"} -> ${nextUid ?? "<guest>"}, caches cleared',
      );
    }

    uidListenable.value = nextUid;
    _uidStreamController.add(nextUid);
  }
}
