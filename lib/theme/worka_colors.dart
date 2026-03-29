import 'package:flutter/material.dart';

class WorkaColors {
  // Semantic roles
  static const Color primaryBlue = Color(0xFF3B6EF5);
  static const Color accentOrange = Color(0xFFFF8A1A);
  static const Color bg = Colors.white;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);

  // Brand (legacy names kept)
  static const Color blue = primaryBlue;
  static const Color orange = accentOrange;
  static const Color blueDark = Color(0xFF2F5BFF);
  static const Color blueLight = Color(0xFF6EA8FF);

  // Layout
  static const Color pageBg = bg; // фон экрана
  static const Color cardBg = surface; // карточка/внутренний фон

  // Text
  static const Color title = textPrimary; // как в макете
  static const Color subtitle = textSecondary; // как в макете
  static const Color muted = Color(0xFF9CA3AF); // светлый текст

  // UI grays
  static const Color divider = border;
  static const Color sliderGrey = Color(0xFFEEF2F7); // фон сегмента
  static const Color bottomBarPlaceholder = Color(0xFFEFF2F6); // серый низ

  // Effects
  static const Color hoverBlue = Color(0xFFEAF1FF);

  static const Color onColored = Colors.white;

  // ---------------------------------------------------------------------------
  // Legacy aliases for backward compatibility.
  // Do NOT remove without migrating all call-sites.
  // ---------------------------------------------------------------------------
  static const Color background = bg;
  static const Color textDark = title;
  static const Color textGreyDark = subtitle;
  static const Color textGrey = muted;
  static const Color fieldBorder = divider;
  static const Color hoverBlueSoft = Color(0x1A578CEC);
  static const Color starYellow = Color(0xFFFFC107);
  static const Color salaryAccent = Color(0xFFF4A62A);
}
