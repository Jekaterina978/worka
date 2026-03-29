import 'package:firebase_auth/firebase_auth.dart';

/// Determines which accounts have admin privileges.
/// Admins bypass all monetization limits and paywalls.
class AdminConfig {
  AdminConfig._();

  /// Emails that always get full admin access.
  static const Set<String> _adminEmails = {
    'katei1@yandex.ru',
    'lev.frolov50@gmail.com',
  };

  /// UIDs that always get full admin access (optional, in addition to emails).
  static const Set<String> _adminUids = {};

  /// Returns true if the currently signed-in user is an admin.
  static bool isAdmin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty && _adminEmails.contains(email)) return true;
    final uid = user.uid.trim();
    if (uid.isNotEmpty && _adminUids.contains(uid)) return true;
    return false;
  }
}
