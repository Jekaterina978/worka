import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_paths.dart';
import '../services/auth_guard.dart';
import '../theme/worka_colors.dart';

/// Универсальный бейдж с инициалами.
/// Поддерживает старый вызов: WorkaInitialsBadge(text: 'AB')
/// Если text == null -> берёт имя/фамилию из users/{uid}, иначе displayName/email.
/// Также показывает оранжевый колокольчик, если есть новые входящие отклики/предложения.
class WorkaInitialsBadge extends StatelessWidget {
  final String? text;
  final double size;

  const WorkaInitialsBadge({
    super.key,
    this.text,
    this.size = 38,
  });

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.characters.take(1).toString().toUpperCase();
    final a = parts.first.characters.take(1).toString().toUpperCase();
    final b = parts.last.characters.take(1).toString().toUpperCase();
    return '$a$b';
  }

  String _normalizeToInitials(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'U';

    final lettersOnly = t.replaceAll(RegExp(r'[^A-Za-zА-Яа-яЁё]'), '');
    if (lettersOnly.length == 2 && t.length <= 3 && !t.contains(' ')) {
      return lettersOnly.toUpperCase();
    }

    if (t.contains('@')) return _initialsFromName(t.split('@').first);
    return _initialsFromName(t);
  }

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    final u = auth.currentUser;
    final effectiveUid = AuthGuard.effectiveUidOrNull();

    Widget circle(String initials, {required bool hasNew}) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: WorkaColors.blue, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: WorkaColors.blue,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.38,
                height: 1.0,
              ),
            ),
          ),
          if (hasNew)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: size * 0.38,
                height: size * 0.38,
                decoration: const BoxDecoration(
                  color: WorkaColors.orange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications,
                  size: size * 0.22,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      );
    }

    final provided = (text ?? '').trim();
    if (provided.isNotEmpty) {
      return circle(_normalizeToInitials(provided), hasNew: false);
    }

    if (effectiveUid == null && u == null) return circle('U', hasNew: false);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(effectiveUid ?? u!.uid).snapshots(),
      builder: (context, snap) {
        debugPrint('WorkaInitialsBadge uid=${u?.uid} effectiveUid=$effectiveUid email=${u?.email} anon=${u?.isAnonymous}');
        final m = snap.data?.data() ?? {};
        final fn = (m['firstName'] ?? m['name'] ?? '').toString().trim();
        final ln = (m['lastName'] ?? '').toString().trim();
        final display = ('$fn $ln').trim();

        final base = display.isNotEmpty
            ? display
            : (((u?.displayName ?? '').trim().isNotEmpty)
                ? (u?.displayName ?? '').trim()
                : (((u?.email ?? '').trim().isNotEmpty) ? (u?.email ?? '').split('@').first : 'U'));

        final uid = (effectiveUid ?? u!.uid).trim();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection(FirestorePaths.notifications)
              .doc(uid)
              .collection('items')
              .where('toUserId', isEqualTo: uid)
              .where('isRead', isEqualTo: false)
              .snapshots(),
          builder: (context, notifSnap) {
            final unreadValid = (notifSnap.data?.docs ?? const []).where((d) {
              final m = d.data();
              final target = (m['targetEntity'] is Map)
                  ? Map<String, dynamic>.from(m['targetEntity'] as Map)
                  : const <String, dynamic>{};
              final entityId = (target['id'] ?? '').toString().trim();
              final payload = m['payload'];
              final hasPayload = payload is Map && payload.isNotEmpty;
              return entityId.isNotEmpty || hasPayload;
            }).length;
            return circle(_normalizeToInitials(base), hasNew: unreadValid > 0);
          },
        );
      },
    );
  }
}
