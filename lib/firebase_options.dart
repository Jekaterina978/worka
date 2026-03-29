import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'config/app_env.dart';

/// Firebase options for each platform and environment.
/// Prod keys are real; dev keys are placeholders and should be replaced with a
/// real non-production project before enabling dev runs.
class DefaultFirebaseOptions {
  static FirebaseOptions currentPlatform(AppEnv env) {
    final platformOptions = switch (defaultTargetPlatform) {
      TargetPlatform.android => _platformOptions(env).android,
      TargetPlatform.iOS => _platformOptions(env).ios,
      TargetPlatform.macOS => _platformOptions(env).macos,
      _ => throw UnsupportedError('Platform not supported'),
    };
    if (kIsWeb) {
      return _platformOptions(env).web;
    }
    return platformOptions;
  }

  /// Pair of prod/dev configs for convenience.
  static _EnvOptions _platformOptions(AppEnv env) {
    return env.isProd ? prod : dev;
  }

  // PROD (worka-416c0) — only when APP_ENV=prod
  static const _EnvOptions prod = _EnvOptions(
    android: FirebaseOptions(
      apiKey: 'AIzaSyA4_GpVy8dHE7vXYs6qniDNbjzZGqJuo6E',
      appId: '1:877366032418:android:504d729b4007bb18ec727b',
      messagingSenderId: '877366032418',
      projectId: 'worka-416c0',
      storageBucket: 'worka-416c0.firebasestorage.app',
    ),
    ios: FirebaseOptions(
      apiKey: 'AIzaSyAZ5uIxkrifGANxa_Ky8BWltclkPEVLNz8',
      appId: '1:877366032418:ios:1ba6642db03f8853ec727b',
      messagingSenderId: '877366032418',
      projectId: 'worka-416c0',
      storageBucket: 'worka-416c0.firebasestorage.app',
      iosBundleId: 'com.worka.app',
    ),
    macos: FirebaseOptions(
      apiKey: 'AIzaSyAZ5uIxkrifGANxa_Ky8BWltclkPEVLNz8',
      appId: '1:877366032418:ios:1ba6642db03f8853ec727b',
      messagingSenderId: '877366032418',
      projectId: 'worka-416c0',
      storageBucket: 'worka-416c0.firebasestorage.app',
      iosBundleId: 'com.worka.app',
    ),
    web: FirebaseOptions(
      apiKey: 'AIzaSyCX2J5KROP9iWO-Xo_CBqZL6VSaUXiXe2g',
      appId: '1:877366032418:web:326d658d1b899fafec727b',
      messagingSenderId: '877366032418',
      projectId: 'worka-416c0',
      authDomain: 'worka-416c0.firebaseapp.com',
      storageBucket: 'worka-416c0.firebasestorage.app',
      measurementId: 'G-G5Y0YG52YB',
    ),
  );

  // DEV/STAGING placeholder — replace with real non-prod config.
  static const _EnvOptions dev = _EnvOptions(
    android: FirebaseOptions(
      apiKey: 'TODO_DEV_API_KEY', // replace with real dev key
      appId: 'TODO_DEV_APP_ID_ANDROID',
      messagingSenderId: 'TODO_DEV_SENDER',
      projectId: 'worka-416c0',
      storageBucket: 'TODO_DEV_BUCKET',
    ),
    ios: FirebaseOptions(
      apiKey: 'TODO_DEV_API_KEY',
      appId: 'TODO_DEV_APP_ID_IOS',
      messagingSenderId: 'TODO_DEV_SENDER',
      projectId: 'worka-416c0',
      storageBucket: 'TODO_DEV_BUCKET',
      iosBundleId: 'com.worka.app.dev', // adjust when real dev project exists
    ),
    macos: FirebaseOptions(
      apiKey: 'TODO_DEV_API_KEY',
      appId: 'TODO_DEV_APP_ID_IOS',
      messagingSenderId: 'TODO_DEV_SENDER',
      projectId: 'worka-416c0',
      storageBucket: 'TODO_DEV_BUCKET',
      iosBundleId: 'com.worka.app.dev',
    ),
    web: FirebaseOptions(
      apiKey: 'TODO_DEV_API_KEY',
      appId: 'TODO_DEV_APP_ID_WEB',
      messagingSenderId: 'TODO_DEV_SENDER',
      projectId: 'worka-416c0',
      authDomain: 'TODO_DEV_AUTH_DOMAIN',
      storageBucket: 'TODO_DEV_BUCKET',
      measurementId: 'TODO_DEV_MEASUREMENT_ID',
    ),
  );
}

class _EnvOptions {
  final FirebaseOptions android;
  final FirebaseOptions ios;
  final FirebaseOptions macos;
  final FirebaseOptions web;

  const _EnvOptions({
    required this.android,
    required this.ios,
    required this.macos,
    required this.web,
  });
}
