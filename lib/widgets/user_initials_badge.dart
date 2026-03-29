import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_paths.dart';
import '../services/auth_guard.dart';
import '../theme/worka_colors.dart';

class UserInitialsBadge extends StatelessWidget {
  final double size; // диаметр кружка
  final bool showIfAnonymous;
  final VoidCallback? onTap;

  const UserInitialsBadge({
    super.key,
    this.size = 34,
    this.showIfAnonymous = false,
    this.onTap,
  });

  String _initialsFrom({
    required Map<String, dynamic>? userDoc,
    required User? user,
  }) {
    final fn = (userDoc?['firstName'] ?? userDoc?['name'] ?? '').toString().trim();
    final ln = (userDoc?['lastName'] ?? '').toString().trim();

    String pick(String s) => s.isEmpty ? '' : s.characters.first.toUpperCase();

    var a = pick(fn);
    var b = pick(ln);

    if (a.isEmpty || b.isEmpty) {
      final dn = (user?.displayName ?? '').trim();
      if (dn.isNotEmpty) {
        final parts = dn.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
        if (a.isEmpty && parts.isNotEmpty) a = pick(parts[0]);
        if (b.isEmpty && parts.length >= 2) b = pick(parts[1]);
      }
    }

    final res = (a + b).trim();
    return res.isEmpty ? 'U' : res;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final effectiveUid = AuthGuard.effectiveUidOrNull();
    if (user == null && effectiveUid == null) return const SizedBox.shrink();
    if (user != null && !showIfAnonymous && user.isAnonymous && effectiveUid == null) return const SizedBox.shrink();

    final ref = FirebaseFirestore.instance.collection('users').doc(effectiveUid ?? user!.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        debugPrint('UserInitialsBadge uid=${user?.uid} effectiveUid=$effectiveUid email=${user?.email} anon=${user?.isAnonymous}');
        final data = snap.data?.data();
        final initials = _initialsFrom(userDoc: data, user: user);

        final uid = (effectiveUid ?? user!.uid).trim();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
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
            final hasNew = unreadValid > 0;
            final child = Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: WorkaColors.blue, width: 2),
                  ),
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

            if (onTap == null) return child;
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: child,
            );
          },
        );
      },
    );
  }
}
