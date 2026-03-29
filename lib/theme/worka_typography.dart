import 'package:flutter/material.dart';
import 'worka_colors.dart';

class WorkaText {
  // Заголовки (как на StartScreen)
  static const TextStyle h1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    height: 1.08,
    fontWeight: FontWeight.w700, // вместо w900
    color: WorkaColors.textDark,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 22,
    height: 1.12,
    fontWeight: FontWeight.w700,
    color: WorkaColors.textDark,
  );

  // Основной серый тонкий (как на референсах)
  static const TextStyle grey = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w400, // тонкий
    color: WorkaColors.textGrey,
  );

  static const TextStyle greyDark = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: WorkaColors.textGreyDark,
  );

  // Текст на кнопках
  static const TextStyle button = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600, // вместо w900
    color: WorkaColors.onColored,
  );

  // Лейблы полей
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: WorkaColors.textGreyDark,
  );

  // Ввод текста
  static const TextStyle field = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600, // вместо w800
    color: WorkaColors.textDark,
  );
}
