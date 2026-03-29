import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../screens/cv/cv_view_screen.dart';

class FullCvPage extends StatelessWidget {
  const FullCvPage({
    super.key,
    required this.cvId,
    this.refOverride,
    this.testMode = true,
    this.startEditing = false,
  });

  final String cvId;
  final DocumentReference<Map<String, dynamic>>? refOverride;
  final bool testMode;
  final bool startEditing;

  @override
  Widget build(BuildContext context) {
    return CvViewScreen(
      cvId: cvId,
      refOverride: refOverride,
      testMode: testMode,
      startEditing: startEditing,
    );
  }
}
