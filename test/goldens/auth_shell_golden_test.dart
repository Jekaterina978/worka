import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:worka/shell/auth_shell.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });

  Widget buildShell({required int initialIndex}) {
    return MaterialApp(
      home: AuthShell(
        initialIndex: initialIndex,
        skipAuthSideEffects: true,
        showUserAvatar: false,
        tabsOverride: const [
          _GoldenTab(
            key: Key('welcome_content'),
            title: 'Домой',
            subtitle: 'WelcomeContent',
            icon: Icons.home_rounded,
          ),
          _GoldenTab(
            key: Key('favorites_content'),
            title: 'Избранное',
            subtitle: 'Favorites content',
            icon: Icons.star_outline_rounded,
          ),
          _GoldenTab(
            key: Key('profile_content'),
            title: 'Профиль',
            subtitle: 'Profile content',
            icon: Icons.person_outline_rounded,
          ),
          _GoldenTab(
            key: Key('contact_content'),
            title: 'Контакт',
            subtitle: 'Contact content',
            icon: Icons.mail_outline_rounded,
          ),
        ],
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester, {
    required int tabIndex,
    required String goldenName,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidgetBuilder(buildShell(initialIndex: tabIndex));
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, goldenName);
  }

  testGoldens('AuthShell home tab golden', (tester) async {
    await expectGolden(tester, tabIndex: 0, goldenName: 'auth_shell_home');
  });

  testGoldens('AuthShell favorites tab golden', (tester) async {
    await expectGolden(
      tester,
      tabIndex: 1,
      goldenName: 'auth_shell_favorites',
    );
  });

  testGoldens('AuthShell profile tab golden', (tester) async {
    await expectGolden(tester, tabIndex: 2, goldenName: 'auth_shell_profile');
  });

  testGoldens('AuthShell contact tab golden', (tester) async {
    await expectGolden(tester, tabIndex: 3, goldenName: 'auth_shell_contact');
  });
}

class _GoldenTab extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _GoldenTab({
    required super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 28, color: const Color(0xFF2563EB)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
