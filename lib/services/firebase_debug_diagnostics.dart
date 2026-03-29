import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseDebugDiagnostics {
  FirebaseDebugDiagnostics._();

  static bool get _enabled => kDebugMode;

  static bool isPermissionDenied(Object? error) {
    final msg = (error ?? '').toString().toLowerCase();
    return msg.contains('permission-denied') || msg.contains('permission_denied');
  }

  static String permissionHintText() {
    return 'Подсказка: Firestore вернул PERMISSION_DENIED. Проверьте Firestore Rules для чтения/записи.';
  }

  static Future<void> debugWritePing() async {
    if (!_enabled) return;
    try {
      final ref = await FirebaseFirestore.instance.collection('ping').add({
        'createdAt': FieldValue.serverTimestamp(),
        'clientAt': DateTime.now().toIso8601String(),
        'projectId': Firebase.app().options.projectId,
        'mode': 'debug',
      });
      debugPrint('Firebase ping write: ping/${ref.id} (project: ${Firebase.app().options.projectId})');
    } catch (e) {
      debugPrint('Firebase ping write failed: $e');
    }
  }
}

