import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService._();

  static String mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Пароль слишком простой';
      case 'email-already-in-use':
        return 'Этот email уже зарегистрирован';
      case 'invalid-email':
        return 'Неверный формат email';
      case 'network-request-failed':
        return 'Проблема с сетью. Проверьте интернет';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуйте позже';
      case 'operation-not-allowed':
        return 'Вход по email/password отключён в Firebase Console';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Неверный email или пароль';
      default:
        return e.message ?? 'Ошибка авторизации';
    }
  }

  static Future<Map<String, dynamic>> ensureUserProfile(User user) async {
    final uid = user.uid.trim();
    if (uid.isEmpty) return <String, dynamic>{};

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await docRef.get();
    final data = snap.data() ?? <String, dynamic>{};

    if (!snap.exists) {
      final displayName = (user.displayName ?? '').trim();
      final parts = displayName.split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first.trim() : '';
      final lastName = parts.length > 1
          ? parts.sublist(1).join(' ').trim()
          : '';
      final email = (user.email ?? '').trim();
      final phone = (user.phoneNumber ?? '').trim();

      final seed = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await docRef.set(seed, SetOptions(merge: true));
      return seed;
    }

    return data;
  }
}
