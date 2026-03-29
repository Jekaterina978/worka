import 'package:flutter/material.dart';

import 'auth_entry_screen.dart';

/// Legacy route preserved for compatibility.
/// Uses the single source-of-truth auth UI.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthEntryScreen();
  }
}
