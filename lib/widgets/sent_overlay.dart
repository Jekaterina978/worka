import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';

Future<void> showSentOverlay(BuildContext context, String text) async {
  final rootNav = Navigator.of(context, rootNavigator: true);
  Future.delayed(const Duration(milliseconds: 1300), () {
    if (rootNav.canPop()) rootNav.pop();
  });

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => Material(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: WorkaColors.orange, size: 62),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: WorkaColors.textDark,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
