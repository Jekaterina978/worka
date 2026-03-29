import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/admin_config.dart';

enum AccountMode { personal, business }

class AppMode {
  AppMode._();

  /// Admins bypass all monetization checks.
  static bool get bypassMonetization => AdminConfig.isAdmin();

  static const String kLegacyTestUid = 'dev';
  static const String kTestUid = 'test_device';
  static const String _kTestOwnerKeyPref = 'worka_test_owner_key';
  static String? _cachedTestOwnerKey;
  static AccountMode _currentMode = AccountMode.personal;
  static final ValueNotifier<AccountMode> modeNotifier =
      ValueNotifier<AccountMode>(AccountMode.personal);

  static AccountMode get currentMode => _currentMode;

  static void setMode(AccountMode mode) {
    _currentMode = mode;
    modeNotifier.value = mode;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kTestOwnerKeyPref)?.trim() ?? '';
    if (existing.isNotEmpty) {
      _cachedTestOwnerKey = existing;
      return;
    }
    final generated = 'test_${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_kTestOwnerKeyPref, generated);
    _cachedTestOwnerKey = generated;
  }

  static String testOwnerKeySync() {
    final cached = _cachedTestOwnerKey?.trim() ?? '';
    if (cached.isNotEmpty) return cached;
    return 'test_fallback';
  }

  static String effectiveUserId({
    required String? authUid,
    required bool testMode,
  }) {
    return effectiveOwnerKey(authUid: authUid, testMode: testMode);
  }

  static String effectiveOwnerKey({
    required String? authUid,
    required bool testMode,
  }) {
    if (authUid != null && authUid.trim().isNotEmpty) return authUid.trim();
    return testMode ? testOwnerKeySync() : '';
  }

  static bool isTestOwner(String ownerUid) {
    final v = ownerUid.trim();
    return v.isEmpty ||
        v == kLegacyTestUid ||
        v == kTestUid ||
        v == testOwnerKeySync();
  }

  static const String _kTestProfileEnabledKey = 'worka_test_profile_enabled';

  static Future<void> setTestProfileEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTestProfileEnabledKey, enabled);
  }

  static Future<bool> isTestProfileEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTestProfileEnabledKey) ?? false;
  }
}
