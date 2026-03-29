import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worka/shell/auth_shell.dart';

void main() {
  Widget buildHarness() {
    return MaterialApp(
      home: AuthShell(
        skipAuthSideEffects: true,
        showUserAvatar: false,
        tabsOverride: const [
          _TabStub(key: Key('welcome_content'), title: 'Home Content'),
          _TabStub(key: Key('favorites_content'), title: 'Favorites Content'),
          _TabStub(key: Key('profile_content'), title: 'Profile Content'),
          _TabStub(key: Key('contact_content'), title: 'Contact Content'),
        ],
      ),
    );
  }

  testWidgets('AuthShell tab order maps to Home/Favorites/Profile/Contact', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('worka_bottom_nav')), findsOneWidget);
    expect(find.byKey(const Key('welcome_content')), findsOneWidget);
    expect(find.byKey(const Key('favorites_content')), findsNothing);
    expect(find.byKey(const Key('profile_content')), findsNothing);
    expect(find.byKey(const Key('contact_content')), findsNothing);

    await tester.tap(find.text('Избранное'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('favorites_content')), findsOneWidget);

    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_content')), findsOneWidget);

    await tester.tap(find.text('Контакт'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact_content')), findsOneWidget);

    await tester.tap(find.text('Домой'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome_content')), findsOneWidget);
  });

  testWidgets(
    'Profile tab does not render Placeholder or red debug container',
    (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();

      expect(find.byType(Placeholder), findsNothing);

      final redContainer = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        if (w.color == Colors.red) return true;
        final decoration = w.decoration;
        if (decoration is BoxDecoration && decoration.color == Colors.red) {
          return true;
        }
        return false;
      }, description: 'Container(color: Colors.red)');
      expect(redContainer, findsNothing);
    },
  );
}

class _TabStub extends StatelessWidget {
  final String title;

  const _TabStub({required super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }
}
