import 'package:flutter/material.dart';

/// ⚠️ В проекте есть основной экран визарда:
///   lib/screens/cv/cv_wizard_screen.dart
/// Этот файл в папке widgets оставлен ТОЛЬКО для совместимости со старыми импортами.
/// Чтобы не было двух разных реализаций, мы просто проксируем на основной.
import '../cv_wizard_screen.dart' as main;

class CvWizardScreen extends StatelessWidget {
  final bool testMode;
  final String? initialStepId;
  final String? existingCvId;

  const CvWizardScreen({
    super.key,
    this.testMode = true,
    this.initialStepId,
    this.existingCvId,
  });

  @override
  Widget build(BuildContext context) {
    return main.CvWizardScreen(
      testMode: testMode,
      initialStepId: initialStepId,
      existingCvId: existingCvId,
    );
  }
}
