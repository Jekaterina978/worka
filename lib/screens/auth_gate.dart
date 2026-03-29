import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'loading_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, User? user) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        debugPrint(
          '[AuthGate] connectionState=${snap.connectionState} '
          'hasData=${snap.hasData} uid=${snap.data?.uid}',
        );
        if (snap.connectionState == ConnectionState.waiting ||
            snap.connectionState == ConnectionState.none) {
          return const LoadingScreen();
        }
        final u = snap.data;
        return builder(context, u);
      },
    );
  }
}
