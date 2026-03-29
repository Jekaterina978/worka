class AuthRedirect {
  AuthRedirect._();

  static int? desiredTabIndex;

  static void setDesiredTabIndex(int index) {
    desiredTabIndex = index;
  }

  static int? consumeDesiredTabIndex() {
    final value = desiredTabIndex;
    desiredTabIndex = null;
    return value;
  }
}
