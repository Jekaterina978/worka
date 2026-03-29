import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_redirect.dart';
import '../shell/auth_shell.dart';
import '../screens/loading_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSub;
  Timer? _logoutDebounce;

  /// Last confirmed UID. Updated immediately when a real user arrives.
  /// Only cleared after [_kLogoutDebounce] of sustained null (genuine logout),
  /// so brief null flashes (token refresh / app resume) don't destroy AuthShell.
  String? _stableUid;
  bool _initialized = false;

  // Debounce to ignore transient null auth (e.g., Stripe return / token refresh).
  static const Duration _kLogoutDebounce = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    // Subscribe in initState — never inside build/builder.
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthUser);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _logoutDebounce?.cancel();
    super.dispose();
  }

  void _onAuthUser(User? user) {
    if (kDebugMode) {
      debugPrint('[AuthGate] auth event uid=${user?.uid} stableUid=$_stableUid');
    }

    if (user != null) {
      // Real user — cancel any pending logout debounce.
      _logoutDebounce?.cancel();
      if (!_initialized || _stableUid != user.uid) {
        setState(() {
          _stableUid = user.uid;
          _initialized = true;
        });
      } else if (!_initialized) {
        setState(() => _initialized = true);
      }
    } else if (!_initialized) {
      // First emission is null → genuinely unauthenticated, no debounce needed.
      setState(() {
        _stableUid = null;
        _initialized = true;
      });
    } else {
      // User went null while we had a valid session. Might be transient token
      // refresh. Debounce before accepting so AuthShell isn't rebuilt needlessly.
      _logoutDebounce?.cancel();
      _logoutDebounce = Timer(_kLogoutDebounce, () {
        if (FirebaseAuth.instance.currentUser == null && mounted) {
          setState(() => _stableUid = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const LoadingScreen();
    }

    // Key on stable UID so AuthShell is only rebuilt on a real user switch
    // (A→B or A→guest after debounce), not on transient null flashes.
    final uid = _stableUid ?? 'guest';
    final initialIndex = _stableUid != null
        ? (AuthRedirect.consumeDesiredTabIndex() ?? 0)
        : 0;
    return AuthShell(
      key: ValueKey(uid),
      initialIndex: initialIndex.clamp(0, 3),
    );
  }
}
