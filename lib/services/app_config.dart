import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // In debug builds we keep public access open for data visibility/testing.
  static const bool debugOpenAccess = kDebugMode;
}
