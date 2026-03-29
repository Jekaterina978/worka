import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths.dart';

class NotificationsRepository {
  NotificationsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _itemsCol(String userId) {
    return _db.collection(FirestorePaths.notifications).doc(userId).collection('items');
  }

  Stream<int> watchUnreadCount(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return Stream.value(0);
    return _itemsCol(uid)
        .where('toUserId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) {
      return snap.docs.where((d) {
        final m = d.data();
        final target = (m['targetEntity'] is Map)
            ? Map<String, dynamic>.from(m['targetEntity'] as Map)
            : const <String, dynamic>{};
        final entityId = (target['id'] ?? '').toString().trim();
        final payload = m['payload'];
        final hasPayload = payload is Map && payload.isNotEmpty;
        return entityId.isNotEmpty || hasPayload;
      }).length;
    });
  }

  Future<void> createItem({
    required String toUserId,
    required String fromUserId,
    required String type,
    required String kind,
    required String entityId,
    Map<String, dynamic>? payload,
  }) async {
    final id = '${type}_${kind}_${entityId}_${DateTime.now().millisecondsSinceEpoch}';
    await _itemsCol(toUserId).doc(id).set({
      'notifId': id,
      'type': type,
      'targetEntity': {
        'kind': kind,
        'id': entityId,
      },
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'payload': payload ?? <String, dynamic>{},
    }, SetOptions(merge: true));
  }

  Future<void> markReadByType(String userId, List<String> types) async {
    if (types.isEmpty) return;
    final snap = await _itemsCol(userId).where('isRead', isEqualTo: false).get();
    for (final d in snap.docs) {
      final type = (d.data()['type'] ?? '').toString();
      if (!types.contains(type)) continue;
      await d.reference.set({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
