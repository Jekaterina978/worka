import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../interactions/offers_list_screen.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key, this.testMode = true});

  final bool testMode;

  @override
  Widget build(BuildContext context) {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    return OffersListScreen(
      testMode: testMode,
      workerUid: uid,
    );
  }
}

