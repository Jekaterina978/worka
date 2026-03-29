import 'package:flutter/material.dart';
import 'package:worka/features/payments/screens/credits_wallet_screen.dart';

/// Compatibility wrapper.
/// Canonical credits UI lives in features/payments/screens/credits_wallet_screen.dart.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CreditsWalletScreen();
  }
}
