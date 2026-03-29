import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/worka_colors.dart';
import 'search/search_screen.dart' as search_v2;

class HomeScreen extends StatefulWidget {
  final bool testMode;

  const HomeScreen({super.key, this.testMode = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _displayName = 'Пользователь';
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
      return;
    }

    try {
      final profile = await AuthService.ensureUserProfile(user);
      final first = (profile['firstName'] ?? '').toString().trim();
      final last = (profile['lastName'] ?? '').toString().trim();
      final full = [first, last].where((e) => e.isNotEmpty).join(' ').trim();

      if (!mounted) return;
      setState(() {
        _displayName = full.isNotEmpty
            ? full
            : ((user.displayName ?? user.email ?? 'Пользователь').trim());
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  Future<void> _logout() async {
    debugPrint('[AUTH] signOut requested from HomeScreen');
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        search_v2.SearchScreen(testMode: widget.testMode),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loadingProfile ? 'Загрузка профиля...' : _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WorkaColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _logout,
                      icon: const Icon(
                        Icons.logout,
                        size: 16,
                        color: WorkaColors.blue,
                      ),
                      label: const Text(
                        'Выйти',
                        style: TextStyle(
                          color: WorkaColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
