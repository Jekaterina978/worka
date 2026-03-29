import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/dual_collection_streams.dart';
import '../services/firestore_paths.dart';
import '../services/app_mode.dart';

class WorkaRepo {
  WorkaRepo(this._db);

  final FirebaseFirestore _db;

  String cvCollection({required bool testMode, required bool authed}) {
    return FirestorePaths.cvsCol(testMode: testMode, authed: authed);
  }

  String jobsCollection({required bool testMode, required bool authed}) {
    return FirestorePaths.jobsCol(testMode: testMode, authed: authed);
  }

  String responsesCollection({required bool testMode, required bool authed}) {
    return FirestorePaths.responsesCol(testMode: testMode, authed: authed);
  }

  CollectionReference<Map<String, dynamic>> responsesRef({
    required bool testMode,
    required bool authed,
  }) {
    return _db.collection(responsesCollection(testMode: testMode, authed: authed));
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMyCvs({
    required bool testMode,
    required String userId,
  }) {
    if (testMode) {
      return DualCollectionStreams.mergeDocs(
        db: _db,
        firstCollection: FirestorePaths.cvs,
        secondCollection: FirestorePaths.cvsTest,
      ).map((docs) => _sortByDatesDesc(docs.where((d) => _isMyTestDoc(d.data(), userId)).toList()));
    }
    return _db.collection(FirestorePaths.cvs).snapshots().map((s) {
      final docs = s.docs.where((d) {
        final m = d.data();
        final ownerKey = (m['ownerKey'] ?? '').toString().trim();
        final ownerUid = (m['ownerUid'] ?? '').toString().trim();
        return ownerKey == userId || ownerUid == userId;
      }).toList();
      return _sortByDatesDesc(docs);
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMyJobs({
    required bool testMode,
    required String userId,
  }) {
    if (testMode) {
      return DualCollectionStreams.mergeDocs(
        db: _db,
        firstCollection: FirestorePaths.jobs,
        secondCollection: FirestorePaths.jobsTest,
      ).map((docs) => _sortByDatesDesc(docs.where((d) => _isMyTestDoc(d.data(), userId)).toList()));
    }
    return _db.collection(FirestorePaths.jobs).snapshots().map((s) {
      final docs = s.docs.where((d) {
        final m = d.data();
        final ownerKey = (m['ownerKey'] ?? '').toString().trim();
        final ownerUid = (m['ownerUid'] ?? '').toString().trim();
        return ownerKey == userId || ownerUid == userId;
      }).toList();
      return _sortByDatesDesc(docs);
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchResponses({
    required bool testMode,
  }) {
    if (testMode) {
      return DualCollectionStreams.mergeDocs(
        db: _db,
        firstCollection: FirestorePaths.responses,
        secondCollection: FirestorePaths.responsesTest,
      ).map((docs) {
        final dedup = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in docs) {
          dedup[d.id] = d;
        }
        return _sortByDatesDesc(dedup.values.toList());
      });
    }
    return responsesRef(testMode: testMode, authed: true).snapshots().map((s) => _sortByDatesDesc([...s.docs]));
  }

  Future<DocumentReference<Map<String, dynamic>>> resolveCvRef({
    required String cvId,
    required bool testMode,
    required bool authed,
  }) async {
    final primaryCol = cvCollection(testMode: testMode, authed: authed);
    final primaryRef = _db.collection(primaryCol).doc(cvId);
    final primarySnap = await primaryRef.get();
    if (primarySnap.exists) return primaryRef;
    final fallbackCol = primaryCol == FirestorePaths.cvsTest ? FirestorePaths.cvs : FirestorePaths.cvsTest;
    return _db.collection(fallbackCol).doc(cvId);
  }

  Future<DocumentReference<Map<String, dynamic>>> resolveJobRef({
    required String jobId,
    required bool testMode,
    required bool authed,
  }) async {
    final primaryCol = jobsCollection(testMode: testMode, authed: authed);
    final primaryRef = _db.collection(primaryCol).doc(jobId);
    final primarySnap = await primaryRef.get();
    if (primarySnap.exists) return primaryRef;
    final fallbackCol = primaryCol == FirestorePaths.jobsTest ? FirestorePaths.jobs : FirestorePaths.jobsTest;
    return _db.collection(fallbackCol).doc(jobId);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByDatesDesc(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    DateTime parseDate(dynamic v) => v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    docs.sort((a, b) {
      final au = parseDate(a.data()['updatedAt']);
      final bu = parseDate(b.data()['updatedAt']);
      if (au != bu) return bu.compareTo(au);
      final ac = parseDate(a.data()['createdAt']);
      final bc = parseDate(b.data()['createdAt']);
      return bc.compareTo(ac);
    });
    return docs;
  }

  bool _isMyTestDoc(Map<String, dynamic> m, String userId) {
    final ownerKey = (m['ownerKey'] ?? '').toString().trim();
    if (ownerKey == userId) return true;
    final ownerUid = (m['ownerUid'] ?? '').toString().trim();
    if (ownerUid == userId) return true;
    if (AppMode.isTestOwner(ownerUid)) {
      final source = (m['source'] ?? '').toString().trim();
      if (source == 'test_anonymous' || ownerUid.isEmpty) return true;
    }
    return false;
  }
}
