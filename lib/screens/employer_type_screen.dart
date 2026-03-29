import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_guard.dart';
import '../services/app_mode.dart';
import '../services/effective_uid.dart';
import '../services/navigation_return_snapshot.dart';
import '../theme/worka_colors.dart';
import 'employer_company_profile_screen.dart';
import '../widgets/worka_header.dart';

class EmployerTypeScreen extends StatefulWidget {
  final bool testMode;

  const EmployerTypeScreen({super.key, this.testMode = false});

  @override
  State<EmployerTypeScreen> createState() => _EmployerTypeScreenState();
}

class _EmployerTypeScreenState extends State<EmployerTypeScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _saving = false;

  void _toast(String t) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(t),
        backgroundColor: WorkaColors.textDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String?> _resolveUidForFlow() =>
      getEffectiveUid(ensureAnonymousIfMissing: true);

  Set<String> _rolesFromUserDoc(Map<String, dynamic> data) {
    final roles = <String>{};
    final rawRoles = data['roles'];
    if (rawRoles is Iterable) {
      for (final item in rawRoles) {
        final v = (item ?? '').toString().trim().toLowerCase();
        if (v.isNotEmpty) roles.add(v);
      }
    }

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'worker') roles.add('worker');
    if (role == 'employer') roles.add('employer_private');
    if (role == 'employer_private' || role == 'employer_company') {
      roles.add(role);
    }
    return roles;
  }

  Future<void> _pick(String type) async {
    final current = _auth.currentUser;
    final effective = AuthGuard.effectiveUidOrNull();
    debugPrint(
      'EmployerTypeScreen._pick type=$type '
      'testMode=${widget.testMode} '
      'currentUserUid=${current?.uid} '
      'currentUserEmail=${current?.email} '
      'isAnonymous=${current?.isAnonymous} '
      'effectiveUid=$effective '
      'route=${ModalRoute.of(context)?.settings.name}',
    );

    final uid = await _resolveUidForFlow();
    if (uid == null) {
      debugPrint(
        'EmployerTypeScreen._pick blocked: uid=null '
        '(currentUser=${current?.uid}, effectiveUid=$effective)',
      );
      _toast('Не удалось определить пользователя. Попробуйте ещё раз.');
      return;
    }

    setState(() => _saving = true);
    try {
      final ref = _db.collection('users').doc(uid);
      final existing = await ref.get();
      final mergedRoles = _rolesFromUserDoc(
        existing.data() ?? const <String, dynamic>{},
      );
      mergedRoles.add(
        type == 'company' ? 'employer_company' : 'employer_private',
      );

      await ref.set({
        'role': 'employer',
        'roles': mergedRoles.toList(),
        'employerType': type, // 'company' | 'private'
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      AppMode.setMode(AccountMode.business);

      if (!mounted) return;

      if (type == 'company') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                EmployerCompanyProfileScreen(initialEmployerType: type),
          ),
        );
        return;
      }

      NavigationReturnSnapshot.captureTab(2);
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    } catch (e, st) {
      debugPrint('EmployerTypeScreen._pick failed: $e');
      debugPrint('EmployerTypeScreen._pick stacktrace: $st');
      _toast('Ошибка: $e');
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
          WorkaHeader(
            title: 'Тип работодателя',
            leading: IconButton(
              onPressed: _saving ? null : () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Кто вы?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: WorkaColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Выберите тип работодателя, чтобы заполнить профиль.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: WorkaColors.textGreyDark,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 16),

            _TypeCard(
              icon: Icons.apartment,
              title: 'Компания',
              subtitle: 'Профиль от имени фирмы (OÜ/AS и т.д.)',
              disabled: _saving,
              onTap: () => _pick('company'),
            ),
            const SizedBox(height: 12),

            _TypeCard(
              icon: Icons.person_outline,
              title: 'Частное лицо',
              subtitle: 'Профиль от себя (без компании)',
              disabled: _saving,
              onTap: () => _pick('private'),
            ),

            const Spacer(),

            if (_saving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool disabled;

  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WorkaColors.divider),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: WorkaColors.divider),
              ),
              child: Icon(icon, color: WorkaColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: WorkaColors.textGreyDark),
          ],
        ),
      ),
    );
  }
}
