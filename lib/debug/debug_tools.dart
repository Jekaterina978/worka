import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths.dart';

class DebugTools {
  static const int _batchLimit = 450;

  static Future<int> clearResponses(FirebaseFirestore db) async {
    final col = db.collection(FirestorePaths.responses);
    int deleted = 0;

    while (true) {
      final snap = await col.limit(_batchLimit).get();
      if (snap.docs.isEmpty) break;

      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }

    return deleted;
  }

  // Очищаем только уведомления, связанные с откликами/предложениями.
  // Фактическая схема в проекте: notifications/{uid}/items.
  static Future<int> clearResponseNotifications(FirebaseFirestore db) async {
    int deleted = 0;

    final items = db.collectionGroup('items');

    deleted += await _deleteByQuery(
      db,
      items.where('targetEntity.kind', isEqualTo: 'response'),
    );
    deleted += await _deleteByQuery(
      db,
      items.where('targetEntity.kind', isEqualTo: 'offer'),
    );

    for (final t in const [
      'response_received',
      'offer_sent',
      'offer_received',
      'status_changed',
    ]) {
      deleted += await _deleteByQuery(
        db,
        items.where('type', isEqualTo: t),
      );
    }

    return deleted;
  }

  static Future<int> _deleteByQuery(
    FirebaseFirestore db,
    Query<Map<String, dynamic>> q,
  ) async {
    int deleted = 0;

    while (true) {
      final snap = await q.limit(_batchLimit).get();
      if (snap.docs.isEmpty) break;

      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }

    return deleted;
  }

  static Future<Map<String, int>> clearAllResponsesAndRelated(
    FirebaseFirestore db,
  ) async {
    final resp = await clearResponses(db);
    final notif = await clearResponseNotifications(db);

    return {
      'responses': resp,
      'notifications': notif,
    };
  }
}
