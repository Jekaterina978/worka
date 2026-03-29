import 'package:flutter/material.dart';

class MonetizationPricing {
  static const String currency = 'EUR';

  // Worker
  static const int workerFreeActiveCvLimit = 5;
  static const int workerPlusExtraCv = 3;
  static const int workerUnlimitedCvLimit = 999;
  static const double workerCvPlus3Monthly = 2.99;
  static const double workerCvUnlimitedMonthly = 5.99;
  static const double boostCv48h = 1.99;
  static const double highlightProfile7d = 2.49;
  static const double prioritySearch7d = 3.99;
  static const double verifiedProfile = 4.99;
  static const double workerPlusMonthly = 4.99;
  static const double highlightCv7d = 2.49;

  // Employer private credits
  static const double contact1 = 3.49;
  static const double contact5 = 14.99;
  static const double contact20 = 49.99;

  // Employer private plans
  static const double privateStarterMonthly = 19.0;
  static const double privatePlusMonthly = 29.0;
  static const int privateFreeActiveJobs = 1;
  static const int privateStarterActiveJobs = 2;
  static const int privatePlusActiveJobs = 3;
  static const int privateFreeCredits = 0;
  static const int privateStarterCredits = 10;
  static const int privatePlusCredits = 20;
  static const int privateStarterBumps = 1;
  static const int privatePlusBumps = 2;
  static const int privateStarterUrgent = 0;
  static const int privatePlusUrgent = 1;

  static String eur(double value) {
    final isInt = value == value.roundToDouble();
    return isInt
        ? '€ ${value.toStringAsFixed(0)}'
        : '€ ${value.toStringAsFixed(2)}';
  }
}

enum EmployerType { private, business, agency }

enum EmployerPlan { privateFree, privateStarter, privatePlus }

const Set<String> kPrivateAllowedCategoryGroups = <String>{
  'Строительство и рабочие специальности',
  'Логистика и производство',
  'Продажи и сервис',
  'Дом и сервис',
  'Общественное питание',
  'Транспорт и авто',
};

const Set<String> kPrivateLockedCategoryGroups = <String>{
  'IT и digital',
  'Офис и администрирование',
  'Финансы',
  'Медицина',
  'Красота и спорт',
};

Color monetizationPrimaryBlue() => const Color(0xFF3B82F6);
Color monetizationAccentOrange() => const Color(0xFFFF8A00);
