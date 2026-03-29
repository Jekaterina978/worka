import 'package:shared_preferences/shared_preferences.dart';

class AuthMock {
  static const String _kLoggedIn = 'worka_mock_logged_in';

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kLoggedIn) ?? false;
  }

  static Future<void> setLoggedIn(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLoggedIn, v);
  }

  static Future<void> logout() async => setLoggedIn(false);
}
