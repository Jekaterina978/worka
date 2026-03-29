import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/entity_validity.dart';
import '../services/firestore_paths.dart';

class CvRepository {
  CvRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMyCvDocs({
    required bool testMode,
    required String userId,
  }) {
    if (userId.trim().isEmpty) return Stream.value(const []);
    debugPrint(
      'CvRepository.watchMyCvDocs uid=$userId query=${FirestorePaths.cvs} where ownerId==uid',
    );
    final stream = _db
        .collection(FirestorePaths.cvs)
        .where('ownerId', isEqualTo: userId)
        .snapshots();
    return stream.map((s) {
      final out = s.docs
          .where(
            (d) =>
                WorkaEntityValidity.isValidOwnerCv(d.data(), ownerUid: userId),
          )
          .toList();
      _sort(out);
      debugPrint('CvRepository result uid=$userId count=${out.length}');
      return out;
    });
  }

  void _sort(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    DateTime parseDate(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    docs.sort((a, b) {
      final au = parseDate(a.data()['updatedAt']);
      final bu = parseDate(b.data()['updatedAt']);
      if (au != bu) return bu.compareTo(au);
      final ac = parseDate(a.data()['createdAt']);
      final bc = parseDate(b.data()['createdAt']);
      return bc.compareTo(ac);
    });
  }
}
