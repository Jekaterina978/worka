import 'package:shared_preferences/shared_preferences.dart';

class UserRolePrefs {
  UserRolePrefs._();

  static const String worker = 'worker';
  static const String employer = 'employer';
  static const String _key = 'selected_user_role';

  static Future<void> setSelectedRole(String role) async {
    final value = role.trim();
    if (value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
  }

  static Future<String?> getSelectedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_key)?.trim();
    if (role == null || role.isEmpty) return null;
    return role;
  }
}
