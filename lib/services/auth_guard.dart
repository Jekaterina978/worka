import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app_config.dart';

class AuthGuard {
  AuthGuard._();

  static String? _cachedGuestUid;

  static void setCachedGuestUid(String? uid) {
    final v = uid?.trim();
    _cachedGuestUid = (v == null || v.isEmpty) ? null : v;
  }

  static String? currentUidOrNull() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) return null;
    return uid;
  }

  static String? effectiveUidOrNull() {
    final uid = currentUidOrNull();
    if (uid != null) return uid;

    final guestUid = _cachedGuestUid?.trim();
    if (guestUid != null && guestUid.isNotEmpty) return guestUid;
    return null;
  }

  static bool isGuestLikeUid(String? uid) {
    final v = uid?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return true;
    return v.startsWith('guest_') ||
        v == 'guest' ||
        v == 'anonymous' ||
        v == 'anon' ||
        v == 'unknown' ||
        v == 'none' ||
        v == 'null' ||
        v == 'undefined' ||
        v == 'test' ||
        v == 'dev';
  }

  static String resolveDataUid({required bool testMode}) {
    if (testMode) {
      return (effectiveUidOrNull() ?? 'debug_user').trim();
    }
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  static bool get isDebugOpenAllEnabled =>
      kDebugMode && AppConfig.debugOpenAccess;

  static bool ensureSignedIn(
    BuildContext context, {
    String message = 'Log in to save',
  }) {
    final uid = currentUidOrNull();
    debugPrint(
      'AuthGuard.ensureSignedIn authUid=$uid debugOpenAll=$isDebugOpenAllEnabled',
    );
    if (uid != null && !isGuestLikeUid(uid)) return true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    return false;
  }
}
