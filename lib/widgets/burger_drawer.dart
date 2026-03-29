import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account/account_switcher_screen.dart';
import '../screens/auth/auth_entry_screen.dart';
import '../screens/cv/cv_wizard_screen.dart';
import '../screens/employer/create_job_screen.dart';
import '../services/app_mode.dart';
import '../services/navigation_return_snapshot.dart';
import '../services/user_role_prefs.dart';
import '../theme/worka_colors.dart';
import '../screens/contact_screen.dart';

class BurgerDrawer extends StatelessWidget {
  final bool testMode;

  const BurgerDrawer({super.key, this.testMode = true});

  static Future<void> open(BuildContext context, {bool testMode = true}) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BurgerDrawer(testMode: testMode),
    );
  }

  Future<void> _openAddCv(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => CvWizardScreen(testMode: testMode)),
    );
  }

  Future<void> _openAddVacancy(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => CreateJobScreen(testMode: testMode)),
    );
  }

  Future<void> _switchProfileMode(BuildContext context) async {
    final next = AppMode.currentMode == AccountMode.personal
        ? AccountMode.business
        : AccountMode.personal;
    AppMode.setMode(next);
    await UserRolePrefs.setSelectedRole(
      next == AccountMode.personal
          ? UserRolePrefs.worker
          : UserRolePrefs.employer,
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == AccountMode.personal
              ? 'Режим: Личный аккаунт'
              : 'Режим: Бизнес',
        ),
      ),
    );
  }

  Future<void> _openAccountSwitcher(BuildContext context) async {
    final routeName = ModalRoute.of(context)?.settings.name;
    final currentTab = NavigationReturnSnapshot.tabIndex ?? 0;
    NavigationReturnSnapshot.startAccountSwitch(
      tabIndex: currentTab,
      originRoute: routeName,
    );
    Navigator.of(context).pop();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AccountSwitcherScreen()));
  }

  Future<void> _logout(BuildContext context) async {
    Navigator.of(context).pop();
    debugPrint('[AUTH] signOut requested from BurgerDrawer');
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openLogin(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
  }

  Future<void> _openRegister(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
  }

  Future<void> _openSupport(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const ContactScreen()));
  }

  Widget _menuTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: WorkaColors.textDark),
      title: Text(
        title,
        style: const TextStyle(
          color: WorkaColors.textDark,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  String _safe(dynamic v) {
    final text = (v ?? '').toString().trim();
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: user == null
              ? _GuestMenu(
                  onAddCv: () => _openAddCv(context),
                  onAddVacancy: () => _openAddVacancy(context),
                  onLogin: () => _openLogin(context),
                  onRegister: () => _openRegister(context),
                  onSupport: () => _openSupport(context),
                )
              : _AuthMenu(
                  uid: user.uid,
                  fallbackEmail: user.email ?? '',
                  onAddCv: () => _openAddCv(context),
                  onAddVacancy: () => _openAddVacancy(context),
                  onSwitchProfile: () => _switchProfileMode(context),
                  onSwitchAccount: () => _openAccountSwitcher(context),
                  onLogout: () => _logout(context),
                  onLogin: () => _openLogin(context),
                  onRegister: () => _openRegister(context),
                  onSupport: () => _openSupport(context),
                  safe: _safe,
                  tileBuilder:
                      ({
                        required IconData icon,
                        required String title,
                        required VoidCallback onTap,
                      }) => _menuTile(
                        context: context,
                        icon: icon,
                        title: title,
                        onTap: onTap,
                      ),
                ),
        ),
      ),
    );
  }
}

class _GuestMenu extends StatelessWidget {
  final VoidCallback onAddCv;
  final VoidCallback onAddVacancy;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onSupport;

  const _GuestMenu({
    required this.onAddCv,
    required this.onAddVacancy,
    required this.onLogin,
    required this.onRegister,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: SizedBox(
              width: 44,
              child: Divider(thickness: 4, color: WorkaColors.fieldBorder),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Гость',
            style: TextStyle(
              color: WorkaColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Добавить CV'),
            onTap: onAddCv,
          ),
          ListTile(
            leading: const Icon(Icons.work_outline_rounded),
            title: const Text('Добавить вакансию'),
            onTap: onAddVacancy,
          ),
          ListTile(
            leading: const Icon(Icons.login_rounded),
            title: const Text('Войти'),
            onTap: onLogin,
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded),
            title: const Text('Создать аккаунт'),
            onTap: onRegister,
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('Поддержка'),
            onTap: onSupport,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _AuthMenu extends StatelessWidget {
  final String uid;
  final String fallbackEmail;
  final VoidCallback onAddCv;
  final VoidCallback onAddVacancy;
  final VoidCallback onSwitchProfile;
  final VoidCallback onSwitchAccount;
  final VoidCallback onLogout;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onSupport;
  final String Function(dynamic) safe;
  final Widget Function({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  })
  tileBuilder;

  const _AuthMenu({
    required this.uid,
    required this.fallbackEmail,
    required this.onAddCv,
    required this.onAddVacancy,
    required this.onSwitchProfile,
    required this.onSwitchAccount,
    required this.onLogout,
    required this.onLogin,
    required this.onRegister,
    required this.onSupport,
    required this.safe,
    required this.tileBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final firstName = safe(data['firstName']);
        final lastName = safe(data['lastName']);
        final fullName = '$firstName $lastName'.trim();
        final email = safe(data['email']);
        final title = fullName.isNotEmpty
            ? fullName
            : (email.isNotEmpty ? email : fallbackEmail);

        return ValueListenableBuilder<AccountMode>(
          valueListenable: AppMode.modeNotifier,
          builder: (context, mode, _) {
            final isBusiness = mode == AccountMode.business;
            final modeLabel = isBusiness ? 'Бизнес' : 'Личный';
            final modeLabelColor = isBusiness
                ? const Color(0xFFFF8904)
                : const Color(0xFF4A6FDB);
            final switchTargetLabel =
                isBusiness ? 'Переключить на Личный' : 'Переключить на Бизнес';

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: WorkaColors.fieldBorder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? 'Пользователь' : title,
                          style: const TextStyle(
                            color: WorkaColors.textDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: modeLabelColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          modeLabel,
                          style: TextStyle(
                            color: modeLabelColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  tileBuilder(
                    icon: Icons.description_outlined,
                    title: 'Добавить CV',
                    onTap: onAddCv,
                  ),
                  tileBuilder(
                    icon: Icons.work_outline_rounded,
                    title: 'Добавить вакансию',
                    onTap: onAddVacancy,
                  ),
                  tileBuilder(
                    icon: Icons.swap_horiz_rounded,
                    title: switchTargetLabel,
                    onTap: onSwitchProfile,
                  ),
                  tileBuilder(
                    icon: Icons.switch_account_rounded,
                    title: 'Сменить аккаунт',
                    onTap: onSwitchAccount,
                  ),
                  tileBuilder(
                    icon: Icons.login_rounded,
                    title: 'Войти',
                    onTap: onLogin,
                  ),
                  tileBuilder(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Создать аккаунт',
                    onTap: onRegister,
                  ),
                  tileBuilder(
                    icon: Icons.support_agent_rounded,
                    title: 'Поддержка',
                    onTap: onSupport,
                  ),
                  tileBuilder(
                    icon: Icons.logout_rounded,
                    title: 'Выйти',
                    onTap: onLogout,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
