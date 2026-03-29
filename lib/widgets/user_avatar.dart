import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../profile/user_profile.dart';
import '../profile/user_profile_repo.dart';
import '../theme/worka_colors.dart';
import '../screens/profile_screen.dart';

enum UserAvatarAction { profile, switchAccount, logout }

class UserAvatar extends StatelessWidget {
  final double size;
  final Future<void> Function()? onProfile;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onSwitchAccount;

  const UserAvatar({
    super.key,
    this.size = 34,
    this.onProfile,
    this.onLogout,
    this.onSwitchAccount,
  });

  String _pickFirst(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    return t.characters.first.toUpperCase();
  }

  String _initials(UserProfile? profile, User user) {
    final firstName = profile?.firstName ?? '';
    final lastName = profile?.lastName ?? '';
    final email =
        (profile?.email.isNotEmpty == true ? profile!.email : user.email ?? '')
            .trim();

    final first = _pickFirst(firstName);
    final last = _pickFirst(lastName);
    if (first.isNotEmpty && last.isNotEmpty) return '$first$last';
    if (first.isNotEmpty) return first;

    final emailFirst = _pickFirst(email);
    if (emailFirst.isNotEmpty) return emailFirst;
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final repo = UserProfileRepo();
    return StreamBuilder<UserProfile?>(
      stream: repo.watchProfile(user.uid),
      builder: (context, snap) {
        final initials = snap.connectionState == ConnectionState.waiting
            ? '...'
            : _initials(snap.data, user);

        final avatar = Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: WorkaColors.blue,
          ),
          child: Text(
            initials,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
              height: 1.0,
            ),
          ),
        );

        return PopupMenuButton<UserAvatarAction>(
          tooltip: 'Меню аккаунта',
          onSelected: (action) async {
            switch (action) {
              case UserAvatarAction.profile:
                if (onProfile != null) {
                  await onProfile!.call();
                  return;
                }
                if (!context.mounted) return;
                await Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
                return;
              case UserAvatarAction.switchAccount:
                if (onSwitchAccount != null) {
                  await onSwitchAccount!.call();
                  return;
                }
                if (onLogout != null) {
                  await onLogout!.call();
                  return;
                }
                debugPrint('[AUTH] signOut requested from UserAvatar switchAccount fallback');
                await FirebaseAuth.instance.signOut();
                return;
              case UserAvatarAction.logout:
                if (onLogout != null) {
                  await onLogout!.call();
                  return;
                }
                debugPrint('[AUTH] signOut requested from UserAvatar logout');
                await FirebaseAuth.instance.signOut();
                return;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem<UserAvatarAction>(
              value: UserAvatarAction.profile,
              child: Text('Профиль'),
            ),
            PopupMenuItem<UserAvatarAction>(
              value: UserAvatarAction.switchAccount,
              child: Text('Сменить аккаунт'),
            ),
            PopupMenuItem<UserAvatarAction>(
              value: UserAvatarAction.logout,
              child: Text('Выйти'),
            ),
          ],
          child: avatar,
        );
      },
    );
  }
}
