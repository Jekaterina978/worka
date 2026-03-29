part of 'package:worka/screens/profile_screen.dart';

class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({
    super.key,
    required this.onEditProfile,
    required this.onSwitchAccount,
    required this.onLogout,
    this.iconColor = WorkaColors.textGreyDark,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onSwitchAccount;
  final VoidCallback onLogout;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ProfileMenuAction>(
      tooltip: 'Меню профиля',
      onSelected: (action) {
        switch (action) {
          case _ProfileMenuAction.editProfile:
            onEditProfile();
            return;
          case _ProfileMenuAction.switchAccount:
            onSwitchAccount();
            return;
          case _ProfileMenuAction.logout:
            onLogout();
            return;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<_ProfileMenuAction>(
          value: _ProfileMenuAction.editProfile,
          child: Text('Редактировать профиль'),
        ),
        PopupMenuItem<_ProfileMenuAction>(
          value: _ProfileMenuAction.switchAccount,
          child: Text('Сменить аккаунт'),
        ),
        PopupMenuItem<_ProfileMenuAction>(
          value: _ProfileMenuAction.logout,
          child: Text('Выйти'),
        ),
      ],
      icon: Icon(Icons.menu_rounded, color: iconColor),
    );
  }
}
