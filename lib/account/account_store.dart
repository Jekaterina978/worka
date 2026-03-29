import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remembered_account.dart';

class AccountStore {
  AccountStore._();

  static const String _key = 'worka_remembered_accounts_v1';
  static const String _activeAccountUidKey = 'worka_active_account_uid_v1';
  static const int _maxAccounts = 10;

  static Future<List<RememberedAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <RememberedAccount>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <RememberedAccount>[];
      final out = <RememberedAccount>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = RememberedAccount.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) out.add(parsed);
      }
      out.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return out;
    } catch (_) {
      return <RememberedAccount>[];
    }
  }

  static Future<void> _saveAccounts(List<RememberedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = [...accounts]
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    final limited = normalized.take(_maxAccounts).toList();
    final encoded = jsonEncode(limited.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static String normalizeProviderId(String providerId) {
    switch (providerId) {
      case 'password':
        return 'password';
      case 'phone':
        return 'phone';
      case 'google.com':
      case 'google':
        return 'google';
      case 'facebook.com':
      case 'facebook':
        return 'facebook';
      default:
        return 'unknown';
    }
  }

  static String detectProvider(User user) {
    final providers = user.providerData
        .map((p) => normalizeProviderId(p.providerId))
        .where((p) => p != 'unknown')
        .toList();
    if (providers.isEmpty) return 'unknown';
    if (providers.contains('password')) return 'password';
    if (providers.contains('phone')) return 'phone';
    if (providers.contains('google')) return 'google';
    if (providers.contains('facebook')) return 'facebook';
    return providers.first;
  }

  static RememberedAccount fromFirebaseUser(User user, {String? provider}) {
    final normalizedProvider = normalizeProviderId(
      (provider ?? detectProvider(user)).trim(),
    );
    return RememberedAccount(
      uid: user.uid,
      email: (user.email ?? '').trim().isEmpty ? null : user.email!.trim(),
      phone: (user.phoneNumber ?? '').trim().isEmpty
          ? null
          : user.phoneNumber!.trim(),
      provider: normalizedProvider,
      displayName: (user.displayName ?? '').trim().isEmpty
          ? null
          : user.displayName!.trim(),
      lastUsed: DateTime.now(),
    );
  }

  static Future<void> addOrUpdate(RememberedAccount account) async {
    final list = await loadAccounts();
    final key = account.stableKey;
    final idx = list.indexWhere(
      (a) => a.uid == account.uid || a.stableKey == key,
    );
    if (idx >= 0) {
      final prev = list[idx];
      list[idx] = account.copyWith(
        email: account.email ?? prev.email,
        phone: account.phone ?? prev.phone,
        displayName: account.displayName ?? prev.displayName,
        provider: account.provider == 'unknown'
            ? prev.provider
            : account.provider,
        lastUsed: DateTime.now(),
      );
    } else {
      list.add(account.copyWith(lastUsed: DateTime.now()));
    }
    await _saveAccounts(list);
    await setActiveAccountUid(account.uid);
  }

  static Future<void> addOrUpdateFromFirebaseUser(
    User user, {
    required String provider,
  }) async {
    final account = fromFirebaseUser(user, provider: provider);
    await addOrUpdate(account);
  }

  static Future<void> setActiveAccountUid(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeAccountUidKey, clean);
  }

  static Future<String?> getActiveAccountUid() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_activeAccountUidKey) ?? '').trim();
    return raw.isEmpty ? null : raw;
  }

  static Future<void> removeAccount(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    final list = await loadAccounts();
    list.removeWhere((a) => a.uid == clean);
    await _saveAccounts(list);
  }

  static Future<RememberedAccount?> getCurrentAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final list = await loadAccounts();
    final idx = list.indexWhere((a) => a.uid == user.uid);
    if (idx >= 0) return list[idx];
    return fromFirebaseUser(user);
  }
}
