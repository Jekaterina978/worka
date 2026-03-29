import 'package:firebase_auth/firebase_auth.dart';

import 'auth_guard.dart';

Future<String?> getEffectiveUid({bool ensureAnonymousIfMissing = false}) async {
  final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
  if (authUid != null && authUid.isNotEmpty) return authUid;

  final effective = AuthGuard.effectiveUidOrNull()?.trim();
  if (effective != null && effective.isNotEmpty) return effective;

  if (!ensureAnonymousIfMissing) return null;

  try {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user?.uid.trim();
    if (uid != null && uid.isNotEmpty) return uid;
  } catch (_) {}
  return null;
}
