import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_mode.dart';
import '../services/auth_guard.dart';
import '../services/user_role_prefs.dart';
import '../theme/worka_colors.dart';
import '../widgets/worka_header.dart';

class RoleSelectScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProfileSeed;

  const RoleSelectScreen({super.key, this.initialProfileSeed});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  String _role = 'worker';
  bool _saving = false;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Set<String> _rolesFromUserDoc(Map<String, dynamic> data) {
    final roles = <String>{};

    final dynamic rawRoles = data['roles'];
    if (rawRoles is Iterable) {
      for (final item in rawRoles) {
        final v = (item ?? '').toString().trim().toLowerCase();
        if (v.isNotEmpty) roles.add(v);
      }
    }

    String normalizeRole(String raw) {
      final v = raw.trim().toLowerCase();
      if (v.isEmpty) return '';
      if (v == 'worker') return 'worker';
      if (v == 'employer_company' || v == 'company') return 'employer_company';
      if (v == 'employer_private' || v == 'private') return 'employer_private';
      if (v == 'employer') return 'employer';
      return '';
    }

    for (final key in ['role', 'profileType', 'userType', 'accountType']) {
      final normalized = normalizeRole((data[key] ?? '').toString());
      if (normalized.isNotEmpty) roles.add(normalized);
    }

    return roles;
  }

  void _toast(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _continue() async {
    debugPrint('RoleSelectScreen: onPress Далее fired, role=$_role');

    setState(() => _saving = true);
    try {
      String? uid = _auth.currentUser?.uid;
      uid ??= AuthGuard.effectiveUidOrNull();

      if (uid == null || uid.isEmpty) {
        debugPrint('RoleSelectScreen: no uid available, trying anonymous auth');
        try {
          final cred = await _auth.signInAnonymously();
          uid = cred.user?.uid;
        } catch (e) {
          debugPrint('RoleSelectScreen: anonymous auth failed: $e');
        }
      }

      if (uid == null || uid.isEmpty) {
        _toast('Не удалось продолжить: отсутствует сессия пользователя');
        return;
      }

      final userRef = _db.collection('users').doc(uid);
      final existing = await userRef.get();
      final existingData = existing.data() ?? const <String, dynamic>{};
      final mergedRoles = _rolesFromUserDoc(existingData);

      final selectedRoleForList = _role == 'worker' ? 'worker' : 'employer';
      mergedRoles.add(selectedRoleForList);

      debugPrint('RoleSelectScreen: saving role/roles to users/$uid');
      await userRef.set({
        'role': _role,
        'roles': mergedRoles.toList(),
        'enabledProfiles': _role == 'worker' ? ['personal'] : ['business'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Persist role and set app mode so profile screen shows correct tab.
      await UserRolePrefs.setSelectedRole(
        _role == 'worker' ? UserRolePrefs.worker : UserRolePrefs.employer,
      );
      AppMode.setMode(
        _role == 'worker' ? AccountMode.personal : AccountMode.business,
      );

      if (!mounted) return;

      debugPrint('RoleSelectScreen: navigate -> main app (role=$_role)');
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e, st) {
      debugPrint('RoleSelectScreen: continue failed: $e');
      debugPrint('RoleSelectScreen: stacktrace: $st');
      _toast('Ошибка продолжения: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(title: 'Кто вы в Worka?'),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                const Text(
                  'Кто вы в Worka?',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: WorkaColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Выберите тип профиля. Это можно изменить позже.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
                const SizedBox(height: 14),

                _PickTile(
                  selected: _role == 'worker',
                  icon: Icons.person_outline,
                  title: 'Работник',
                  subtitle: 'Ищу работу, создаю резюме',
                  onTap: () {
                    debugPrint('RoleSelectScreen: selected role=worker');
                    setState(() => _role = 'worker');
                  },
                ),
                const SizedBox(height: 10),
                _PickTile(
                  selected: _role == 'employer',
                  icon: Icons.business_outlined,
                  title: 'Работодатель',
                  subtitle: 'Размещаю вакансии, ищу кандидатов',
                  onTap: () {
                    debugPrint('RoleSelectScreen: selected role=employer');
                    setState(() => _role = 'employer');
                  },
                ),

                const SizedBox(height: 16),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WorkaColors.orange,
                      foregroundColor: WorkaColors.onColored,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Далее',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PickTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: WorkaColors.hoverBlueSoft,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: WorkaColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: WorkaColors.blue),
          ],
        ),
      ),
    );
  }
}
