import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_mode.dart';

/// Minimal ownership context foundation.
/// Holds current user id, active profile type, and optional profile/company ids.
class OwnershipContext extends ChangeNotifier {
  OwnershipContext({
    FirebaseAuth? auth,
    AppModeProvider? appModeProvider,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _appModeProvider = appModeProvider ?? const AppModeProvider();

  final FirebaseAuth _auth;
  final AppModeProvider _appModeProvider;

  String get currentUserUid => (_auth.currentUser?.uid ?? '').trim();

  AccountMode get activeProfileType => _appModeProvider.currentMode;

  /// Nullable until business/profile selection is implemented.
  String? _activeProfileId;
  String? _activeCompanyId;

  String? get activeProfileId => _activeProfileId;
  String? get activeCompanyId => _activeCompanyId;

  /// Setters keep values trimmed and notify listeners when changed.
  void setActiveProfileId(String? value) {
    final next = value?.trim();
    if (next == _activeProfileId) return;
    _activeProfileId = next?.isEmpty ?? true ? null : next;
    notifyListeners();
  }

  void setActiveCompanyId(String? value) {
    final next = value?.trim();
    if (next == _activeCompanyId) return;
    _activeCompanyId = next?.isEmpty ?? true ? null : next;
    notifyListeners();
  }
}

/// Lightweight provider over AppMode to allow mocking/testing.
class AppModeProvider {
  const AppModeProvider();
  AccountMode get currentMode => AppMode.currentMode;
}
