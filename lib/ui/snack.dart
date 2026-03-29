import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';

class UiSnack {
  UiSnack._();

  static void show(
    BuildContext context,
    String message, {
    Color background = WorkaColors.textDark,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
