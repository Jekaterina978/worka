// ignore_for_file: avoid_print
// dart:html is only available on Flutter web — this file is only imported there.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void webNavigateTo(String url) {
  // Direct assignment is NOT subject to browser popup-blocker restrictions,
  // unlike window.open(). Works even after multiple awaits.
  print('[PAYMENT DEBUG] webNavigateTo via html.window.location.href url=$url');
  html.window.location.href = url;
}
