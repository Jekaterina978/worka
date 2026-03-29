import 'package:flutter/material.dart';

class WorkaTheme {
  // ✅ новый синий
  static const Color blue = Color(0xFF4C69B8);
  static const Color blueHover = Color(0xFF3F5DAE);
  static const Color blueSoft = Color(0xFFEAF1FF);

  static const Color orange = Color(0xFFFF7A00);
  static const Color orangeHover = Color(0xFFEA6E00);

  static const Color divider = Color(0xFFEDEDED);
  static const Color sliderGrey = Color(0xFFF2F2F2);

  // ✅ текст
  static const Color textBlack = Color(0xFF111111);
  static const Color textGrey = Color(0xFF4B4B4B);
  static const Color textHint = Color(0xFF8A8A8A);

  // ✅ избранное
  static const Color starYellow = Color(0xFFFFC107);

  static const List<Color> blueGrad = [Color(0xFF5B77C7), Color(0xFF4C69B8)];
  static const List<Color> orangeGrad = [Color(0xFFFF8A1A), Color(0xFFFF7A00)];

  /// ✅ ЕДИНАЯ ТЕМА: Inter + “как на главном”
  /// Важно: никаких w900/w800 — они и дают “жирный размазанный” вид.
  static ThemeData light() {
    const font = 'Inter';

    final base = ThemeData.light(useMaterial3: true);

    // 1) Применяем Inter ко всему тексту
    final applied = base.textTheme.apply(
      fontFamily: font,
      bodyColor: textBlack,
      displayColor: textBlack,
    );

    // 2) Настраиваем аккуратные веса/цвета (тонко/чисто)
    final tt = applied.copyWith(
      // Заголовки
      displaySmall: applied.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: textBlack,
      ),
      headlineMedium: applied.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: textBlack,
      ),
      titleLarge: applied.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: textBlack,
      ),
      titleMedium: applied.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: textBlack,
      ),

      // Тело/подписи
      bodyLarge: applied.bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        color: textGrey,
      ),
      bodyMedium: applied.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        color: textGrey,
      ),
      labelLarge: applied.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: textBlack,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: tt,
      primaryTextTheme: tt,

      colorScheme: base.colorScheme.copyWith(
        primary: blue,
        secondary: orange,
        surface: Colors.white,
      ),

      // AppBar — как на референсе: чисто, без жирноты
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textBlack),
        titleTextStyle: tt.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: textBlack,
        ),
      ),

      // Поля ввода — тонкие серые hint/label
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        labelStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w400,
          color: textHint,
        ),
        hintStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w400,
          color: textHint,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: blue, width: 1.6),
        ),
      ),

      // Кнопки — текст белый, вес не жирный
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: font,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
