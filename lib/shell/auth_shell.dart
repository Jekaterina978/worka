import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'dart:async';

import '../profile/user_profile_repo.dart';
import '../screens/role_select_screen.dart';
import '../services/app_mode.dart';
import '../services/navigation_return_snapshot.dart';
import '../screens/home/unified_search_filters.dart';
import '../tabs/contact_tab.dart';
import '../tabs/favorites_tab.dart';
import '../tabs/home_tab.dart';
import '../tabs/profile_tab.dart';
import '../screens/favorites_screen.dart' show FavoritesGoHomeNotification;
import '../widgets/ui/bottom_navigation_bar.dart';

class AuthShell extends StatefulWidget {
  final int initialIndex;
  final bool skipAuthSideEffects;
  final bool showUserAvatar;
  final List<Widget>? tabsOverride;

  const AuthShell({
    super.key,
    this.initialIndex = 0,
    this.skipAuthSideEffects = false,
    this.showUserAvatar = true,
    this.tabsOverride,
  });

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  late int _index = widget.initialIndex.clamp(0, 3);
  bool _showBottomNav = true;
  double _scrollAccumulator = 0;
  static const double _scrollThreshold = 12;
  UserProfileRepo? _profileRepo;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  late final List<Widget> _tabs;
  StreamSubscription<User?>? _authSub;
  Timer? _authNullDebounce;
  String _sessionUid = '';
  bool _roleChecked = false;

  @override
  void initState() {
    super.initState();
    _tabs =
        widget.tabsOverride ??
        const [HomeTab(), FavoritesTab(), ProfileTab(), ContactTab()];
    _sessionUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    final restoredIndex = NavigationReturnSnapshot.tabIndex;
    if (restoredIndex != null) {
      _index = restoredIndex.clamp(0, 3);
    }
    if (!widget.skipAuthSideEffects) {
      _profileRepo = UserProfileRepo();
      _ensureProfile();
    } else {
      _roleChecked = true;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authNullDebounce?.cancel();
    super.dispose();
  }

  void _onAuthChanged(User? user) {
    final nextUid = user?.uid.trim() ?? '';
    if (nextUid == _sessionUid) return;

    if (nextUid.isEmpty && _sessionUid.isNotEmpty) {
      // UID went null while we had a real session. This can be a transient
      // token-refresh event. Debounce before reacting so we don't pop all
      // routes on a momentary null that resolves within ~1500 ms (Stripe return, app resume).
      _authNullDebounce?.cancel();
      _authNullDebounce = Timer(const Duration(milliseconds: 1500), () {
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) return; // auth was restored — ignore
        // Genuine sign-out confirmed after debounce.
        _applyUidChange('');
      });
      return;
    }

    _authNullDebounce?.cancel();
    _applyUidChange(nextUid);
  }

  void _applyUidChange(String nextUid) {
    if (nextUid == _sessionUid) return;

    if (kDebugMode) {
      debugPrint(
        'AuthShell uid changed ${_sessionUid.isEmpty ? "<guest>" : _sessionUid} -> ${nextUid.isEmpty ? "<guest>" : nextUid}. Resetting session UI state.',
      );
    }

    final switchInProgress = NavigationReturnSnapshot.accountSwitchInProgress;
    _sessionUid = nextUid;

    if (switchInProgress) {
      if (nextUid.isNotEmpty) {
        NavigationReturnSnapshot.finishAccountSwitch();
      }
      if (mounted) setState(() {});
      return;
    }

    NavigationReturnSnapshot.clearPendingDetails();
    NavigationReturnSnapshot.setHomeMode(SearchMode.vacancies);

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        while (nav.canPop()) {
          nav.pop();
        }
      });
      setState(() {});
    }
  }

  Future<void> _ensureProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _roleChecked = true);
      return;
    }
    try {
      await _profileRepo?.ensureProfileExists(user: user);
      if (!mounted) return;
      final needsRole = await _needsRoleSelect(user.uid);
      if (!mounted) return;
      if (!needsRole) await _restoreAccountMode(user.uid);
      if (needsRole) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => const RoleSelectScreen()))
              .then((_) {
            if (mounted) setState(() => _roleChecked = true);
          });
        });
      } else {
        setState(() => _roleChecked = true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthShell] ensureProfile failed: $e');
      }
      if (mounted) setState(() => _roleChecked = true);
    }
  }

  Future<bool> _needsRoleSelect(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      return data == null ||
          (!(data['role']?.toString().trim().isNotEmpty ?? false) &&
              !((data['enabledProfiles'] as List?)?.isNotEmpty ?? false));
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreAccountMode(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data();
      if (data == null) return;

      final profiles = (data['enabledProfiles'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      final hasBusiness = profiles.contains('business');
      final hasPersonal = profiles.contains('personal');

      if (hasBusiness && !hasPersonal) {
        AppMode.setMode(AccountMode.business);
        return;
      }

      if (hasPersonal && !hasBusiness) {
        AppMode.setMode(AccountMode.personal);
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[AuthShell] skip forced mode restore; '
          'profiles=$profiles current=${AppMode.currentMode.name}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthShell] restoreAccountMode failed: $e');
      }
    }
  }

  void _onTabTap(int index) {
    if (kDebugMode) {
      debugPrint('BottomNav -> switch tab $index');
    }
    setState(() {
      _index = index;
      _showBottomNav = true;
      _scrollAccumulator = 0;
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification.metrics.pixels <= 24) {
      if (!_showBottomNav) {
        setState(() => _showBottomNav = true);
      }
      _scrollAccumulator = 0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() < 0.5) return false;
      _scrollAccumulator += delta;

      if (_scrollAccumulator >= _scrollThreshold && _showBottomNav) {
        setState(() => _showBottomNav = false);
        _scrollAccumulator = 0;
      } else if (_scrollAccumulator <= -_scrollThreshold && !_showBottomNav) {
        setState(() => _showBottomNav = true);
        _scrollAccumulator = 0;
      }
      return false;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _scrollAccumulator = 0;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleChecked) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4A6FDB),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: Stack(
          children: [
            PageStorage(
              bucket: _pageStorageBucket,
              child: NotificationListener<FavoritesGoHomeNotification>(
                onNotification: (notification) {
                  if (_index != 0) {
                    setState(() => _index = 0);
                  }
                  return true;
                },
                child: IndexedStack(index: _index, children: _tabs),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: _showBottomNav ? Offset.zero : const Offset(0, 1.1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  opacity: _showBottomNav ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showBottomNav,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 12,
                            spreadRadius: 0,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: WorkaBottomNavigationBar(
                        currentIndex: _index,
                        onTap: _onTabTap,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
