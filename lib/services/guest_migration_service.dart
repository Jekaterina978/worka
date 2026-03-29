import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_paths.dart';

class GuestMigrationService {
  GuestMigrationService._();

  static const int _batchLimit = 400;

  static Future<void> migrate({
    required FirebaseFirestore db,
    required String guestUid,
    required String userUid,
    required bool testMode,
  }) async {
    final guest = guestUid.trim();
    final user = userUid.trim();
    if (guest.isEmpty || user.isEmpty) return;
    if (guest == user) return;

    await _migrateCollectionField(
      db: db,
      collectionPath: testMode
          ? FirestorePaths.vacanciesTest
          : FirestorePaths.vacancies,
      field: 'ownerId',
      fromValue: guest,
      toValue: user,
    );

    await _migrateCollectionField(
      db: db,
      collectionPath: testMode ? FirestorePaths.cvsTest : FirestorePaths.cvs,
      field: 'ownerId',
      fromValue: guest,
      toValue: user,
    );

    final applicationsCollection = FirestorePaths.applications;
    final jobOffersCollection = FirestorePaths.jobOffers;

    await _migrateCollectionField(
      db: db,
      collectionPath: applicationsCollection,
      field: 'candidateOwnerId',
      fromValue: guest,
      toValue: user,
    );

    await _migrateCollectionField(
      db: db,
      collectionPath: applicationsCollection,
      field: 'employerOwnerId',
      fromValue: guest,
      toValue: user,
    );

    await _migrateCollectionField(
      db: db,
      collectionPath: jobOffersCollection,
      field: 'candidateOwnerId',
      fromValue: guest,
      toValue: user,
    );

    await _migrateCollectionField(
      db: db,
      collectionPath: jobOffersCollection,
      field: 'employerOwnerId',
      fromValue: guest,
      toValue: user,
    );
  }

  static Future<void> _migrateCollectionField({
    required FirebaseFirestore db,
    required String collectionPath,
    required String field,
    required String fromValue,
    required String toValue,
  }) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;

    while (true) {
      Query<Map<String, dynamic>> query = db
          .collection(collectionPath)
          .where(field, isEqualTo: fromValue)
          .orderBy(FieldPath.documentId)
          .limit(_batchLimit);

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) break;

      var batch = db.batch();
      var batchSize = 0;

      for (final doc in snap.docs) {
        batch.update(doc.reference, <String, dynamic>{field: toValue});
        batchSize++;
        if (batchSize >= _batchLimit) {
          await batch.commit();
          batch = db.batch();
          batchSize = 0;
        }
      }

      if (batchSize > 0) {
        await batch.commit();
      }

      cursor = snap.docs.last;
      if (snap.docs.length < _batchLimit) break;
    }
  }
}
