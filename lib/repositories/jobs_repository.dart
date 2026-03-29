import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/firestore_paths.dart';
import '../services/entity_validity.dart';

class JobsRepository {
  JobsRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchSearchJobs({
    required bool testMode,
  }) {
    return _db.collection(FirestorePaths.vacancies).snapshots().map((s) {
      return _sorted(
        s.docs
            .where((d) => WorkaEntityValidity.isValidPublicVacancy(d.data()))
            .toList(),
      );
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMyJobs({
    required bool testMode,
    required String userId,
    String? ownerType,
  }) {
    if (userId.trim().isEmpty) return Stream.value(const []);
    debugPrint(
      'JobsRepository.watchMyJobs uid=$userId ownerType=$ownerType '
      'query=${FirestorePaths.vacancies}',
    );
    final stream = _db
        .collection(FirestorePaths.vacancies)
        .where('ownerId', isEqualTo: userId)
        .snapshots();
    return stream.map((s) {
      var docs = s.docs
          .where(
            (d) => WorkaEntityValidity.isValidOwnerVacancy(
              d.data(),
              ownerUid: userId,
            ),
          )
          .toList();
      // Client-side filter by ownerType.  Docs without ownerType are treated
      // as 'personal' for backwards-compatibility.
      if (ownerType != null && ownerType.trim().isNotEmpty) {
        docs = docs.where((d) {
          final t = (d.data()['ownerType'] ?? 'personal').toString().trim();
          return t == ownerType.trim();
        }).toList();
      }
      final out = _sorted(docs);
      debugPrint(
        'JobsRepository result uid=$userId ownerType=$ownerType count=${out.length}',
      );
      return out;
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    DateTime parseDate(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    docs.sort((a, b) {
      final ac = parseDate(a.data()['createdAt']);
      final bc = parseDate(b.data()['createdAt']);
      if (ac != bc) return bc.compareTo(ac);
      final au = parseDate(a.data()['updatedAt']);
      final bu = parseDate(b.data()['updatedAt']);
      return bu.compareTo(au);
    });
    return docs;
  }
}
