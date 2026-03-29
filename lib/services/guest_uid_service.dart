import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class GuestUidService {
  GuestUidService._();

  static const _key = 'guest_uid';

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final uid =
        'guest_${DateTime.now().millisecondsSinceEpoch}_${(100000 + Random().nextInt(900000))}';
    await prefs.setString(_key, uid);
    return uid;
  }
}
