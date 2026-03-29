import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'user_profile.dart';

class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<UserProfile?> watchByUid(String uid) {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const Stream<UserProfile?>.empty();

    return _firestore.collection('users').doc(cleanUid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return UserProfile.fromMap(data, uid: cleanUid);
    });
  }

  Future<void> ensureProfileExists(User user) async {
    final uid = user.uid.trim();
    if (uid.isEmpty) return;

    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set(<String, dynamic>{
      'firstName': '',
      'lastName': '',
      'email': (user.email ?? '').trim(),
      'phone': (user.phoneNumber ?? '').trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
