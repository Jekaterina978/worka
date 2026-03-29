import 'package:flutter/material.dart';

import 'start_screen.dart';

/// Welcome is outside AppShell, so it has no persistent bottom navigation.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StartScreen(inShell: false);
  }
}
