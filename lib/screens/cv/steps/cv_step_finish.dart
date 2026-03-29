import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepFinish extends StatelessWidget {
  const CvStepFinish({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_outline, size: 64, color: WorkaColors.blue),
            SizedBox(height: 12),
            Text('Готово!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            SizedBox(height: 8),
            Text(
              'Ваше CV заполнено по шагам. Нажмите “Готово”, чтобы выйти.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
