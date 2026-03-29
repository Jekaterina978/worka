enum AppEnv {
  dev,
  prod;

  static AppEnv _fromString(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'prod' || value == 'production') return AppEnv.prod;
    // Default to dev for unknown/empty values to avoid accidental prod usage.
    return AppEnv.dev;
  }

  static AppEnv get current =>
      _fromString(const String.fromEnvironment('APP_ENV', defaultValue: 'dev'));

  bool get isProd => this == AppEnv.prod;
  bool get isDev => this == AppEnv.dev;
}
