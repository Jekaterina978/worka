import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_mode.dart';
import 'firestore_paths.dart';

class TestDataMigrationService {
  TestDataMigrationService._();

  static bool _didRun = false;

  static Future<void> run(FirebaseFirestore db) async {
    if (_didRun) return;
    _didRun = true;

    final ownerKey = AppMode.testOwnerKeySync();
    if (ownerKey.trim().isEmpty) return;

    await _patchOwnerKey(db, FirestorePaths.cvsTest, ownerKey, testOnly: false);
    await _patchOwnerKey(db, FirestorePaths.jobsTest, ownerKey, testOnly: false);
    await _patchOwnerKey(db, FirestorePaths.candidates, ownerKey, testOnly: true);
    await _patchInteractionOwners(
      db,
      FirestorePaths.applications,
      ownerKey,
      testOnly: true,
    );
    await _patchInteractionOwners(
      db,
      FirestorePaths.jobOffers,
      ownerKey,
      testOnly: true,
    );
  }

  static Future<void> _patchOwnerKey(
    FirebaseFirestore db,
    String col,
    String ownerKey, {
    required bool testOnly,
  }) async {
    final snap = await db.collection(col).get();
    for (final d in snap.docs) {
      final m = d.data();
      final hasOwnerKey = (m['ownerKey'] ?? '').toString().trim().isNotEmpty;
      if (hasOwnerKey) continue;
      final isTestDoc = (m['test'] ?? false) == true || (m['source'] ?? '').toString() == 'test_anonymous';
      if (testOnly && !isTestDoc) continue;
      await d.reference.set({
        'ownerKey': ownerKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<void> _patchInteractionOwners(
    FirebaseFirestore db,
    String col,
    String ownerKey, {
    required bool testOnly,
  }) async {
    final snap = await db.collection(col).get();
    for (final d in snap.docs) {
      final m = d.data();
      final meta = (m['meta'] is Map<String, dynamic>) ? (m['meta'] as Map<String, dynamic>) : <String, dynamic>{};
      final isTestDoc = (meta['testMode'] ?? false) == true || (m['test'] ?? false) == true;
      if (testOnly && !isTestDoc) continue;
      final patch = <String, dynamic>{};
      if ((m['candidateOwnerId'] ?? '').toString().trim().isEmpty &&
          ((m['candidateUid'] ?? m['workerId'] ?? m['applicantUid'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty ||
              isTestDoc)) {
        patch['candidateOwnerId'] = (m['candidateUid'] ??
                    m['workerId'] ??
                    m['applicantUid'] ??
                    '')
                .toString()
                .trim()
                .isEmpty
            ? ownerKey
            : (m['candidateUid'] ?? m['workerId'] ?? m['applicantUid'])
                  .toString()
                  .trim();
      }
      if ((m['employerOwnerId'] ?? '').toString().trim().isEmpty &&
          ((m['employerUid'] ?? '').toString().trim().isNotEmpty || isTestDoc)) {
        final val = (m['employerUid'] ?? '').toString().trim();
        patch['employerOwnerId'] = val.isEmpty ? ownerKey : val;
      }
      if (patch.isEmpty) continue;
      patch['updatedAt'] = FieldValue.serverTimestamp();
      await d.reference.set(patch, SetOptions(merge: true));
    }
  }
}
