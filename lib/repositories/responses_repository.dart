import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/dual_collection_streams.dart';
import '../services/firestore_paths.dart';

class ResponsesRepository {
  ResponsesRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchAll({required bool testMode}) {
    if (testMode) {
      return DualCollectionStreams.mergeDocs(
        db: _db,
        firstCollection: FirestorePaths.responses,
        secondCollection: FirestorePaths.responsesTest,
      );
    }
    return _db.collection(FirestorePaths.responses).snapshots().map((s) => s.docs);
  }
}
