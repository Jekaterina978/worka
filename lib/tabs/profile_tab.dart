import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/cv/my_cvs_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/auth/auth_entry_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin<ProfileTab> {
  @override
  bool get wantKeepAlive => true;

  StreamSubscription<User?>? _authSub;
  Timer? _nullDebounce;
  User? _stableUser;

  // Debounce identical to AuthGate/AuthShell — ignores transient null events
  // caused by app resume from Stripe browser (Android Chrome Custom Tab /
  // iOS SFSafariViewController token-refresh window).
  static const Duration _kNullDebounce = Duration(milliseconds: 2000);

  @override
  void initState() {
    super.initState();
    _stableUser = FirebaseAuth.instance.currentUser;
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _nullDebounce?.cancel();
    super.dispose();
  }

  void _onAuthChanged(User? user) {
    if (user != null) {
      _nullDebounce?.cancel();
      if (_stableUser?.uid != user.uid && mounted) {
        setState(() => _stableUser = user);
      }
    } else {
      _nullDebounce?.cancel();
      _nullDebounce = Timer(_kNullDebounce, () {
        if (FirebaseAuth.instance.currentUser == null && mounted) {
          setState(() => _stableUser = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_stableUser == null) {
      return const AuthEntryScreen();
    }
    return const _ProfileTabBody();
  }
}

class _ProfileTabBody extends StatefulWidget {
  const _ProfileTabBody();

  @override
  State<_ProfileTabBody> createState() => _ProfileTabBodyState();
}

class _ProfileTabBodyState extends State<_ProfileTabBody> {
  bool _showMyCvs = false;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint(
        '[_ProfileTabBody build] _showMyCvs=$_showMyCvs parent=${context.widget.runtimeType}',
      );
    }
    return KeyedSubtree(
      key: const Key('profile_content'),
      child: Column(
        children: [
          Expanded(
            child: _showMyCvs
                ? MyCvsScreen(
                    testMode: false,
                    embeddedInShell: true,
                    onBack: () => setState(() => _showMyCvs = false),
                  )
                : ProfileScreen(
                    testMode: false,
                    embeddedInShell: true,
                    onOpenMyCvs: () {
                      if (kDebugMode) {
                        debugPrint(
                          '[_ProfileTabBody] opening MyCvs via embedded path',
                        );
                      }
                      setState(() => _showMyCvs = true);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
