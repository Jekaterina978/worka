import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'home_screen.dart';
import 'loading_screen.dart';
import 'start_screen.dart';
import '../services/app_mode.dart';

class StartRouterScreen extends StatelessWidget {
  final bool testMode;
  final User? currentUser;
  const StartRouterScreen({super.key, this.testMode = true, this.currentUser});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AppMode.isTestProfileEnabled(),
      builder: (context, profileSnap) {
        if (profileSnap.connectionState != ConnectionState.done) {
          return const LoadingScreen();
        }
        final testProfileEnabled = profileSnap.data ?? false;
        final u = currentUser;
        debugPrint('StartRouter auth uid=${u?.uid} email=${u?.email} anon=${u?.isAnonymous} testMode=$testMode testProfile=$testProfileEnabled');
        if (u != null) {
          return const AppShell(
            initialIndex: 0,
            homeRoot: HomeScreen(testMode: true),
          );
        }

        return const StartScreen(inShell: false);
      },
    );
  }
}
