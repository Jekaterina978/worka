import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:worka/debug/debug_tools.dart';
import 'package:worka/services/firestore_paths.dart';

class DevFirestoreDiagnosticsScreen extends StatefulWidget {
  const DevFirestoreDiagnosticsScreen({super.key});

  @override
  State<DevFirestoreDiagnosticsScreen> createState() =>
      _DevFirestoreDiagnosticsScreenState();
}

class _DevFirestoreDiagnosticsScreenState
    extends State<DevFirestoreDiagnosticsScreen> {
  bool _cleaning = false;

  Future<bool> _confirmClearResponses(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить отклики/предложения + уведомления?'),
        content: const Text(
          'Будут удалены документы из responses и связанные уведомления response/offer. CV/jobs/users не затрагиваются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  bool _isProdProjectId(String projectId) => projectId == 'worka-416c0';

  Future<void> _clearResponsesAndNotifications(BuildContext context) async {
    final confirmed = await _confirmClearResponses(context);
    if (!confirmed || !context.mounted) return;

    final currentProject = Firebase.app().options.projectId ?? '';
    if (_isProdProjectId(currentProject)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Production environment detected. Destructive debug actions are disabled.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _cleaning = true);
    try {
      final r = await DebugTools.clearAllResponsesAndRelated(
        FirebaseFirestore.instance,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Очищено: responses=${r['responses']}, уведомления=${r['notifications']}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка очистки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _attachOrphanCvsToCurrentUser(BuildContext context, String uid) async {
    if (uid.isEmpty) return;
    final currentProject = Firebase.app().options.projectId ?? '';
    if (_isProdProjectId(currentProject)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Production environment detected. Destructive debug actions are disabled.',
            ),
          ),
        );
      }
      return;
    }
    final db = FirebaseFirestore.instance;
    final q = await db.collection(FirestorePaths.cvs).limit(50).get();
    var updated = 0;
    for (final d in q.docs) {
      final ownerId = (d.data()['ownerId'] ?? '').toString().trim();
      if (ownerId.isNotEmpty) continue;
      await d.reference.set({
        'ownerId': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      updated += 1;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attached orphan cvs: $updated')),
      );
    }
  }

  Widget _block({
    required String title,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('count=${docs.length}'),
              const SizedBox(height: 6),
              if (docs.isNotEmpty)
                Text(
                  'first: id=${docs.first.id}, ownerId=${(docs.first.data()['ownerId'] ?? '').toString()}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final uid = u?.uid ?? '';
    final db = FirebaseFirestore.instance;
    final projectId = Firebase.app().options.projectId;
    final appName = Firebase.app().name;
    final isProd = _isProdProjectId(projectId ?? '');
    final host = db.settings.host ?? '';
    final usesEmulator = host.isNotEmpty && host != 'firestore.googleapis.com';
    final orphanCvsStream = db.collection(FirestorePaths.cvs).where('ownerId', isEqualTo: '').limit(1).snapshots();
    debugPrint('DevDiagnostics uid=${u?.uid} email=${u?.email} anon=${u?.isAnonymous}');

    return Scaffold(
      appBar: AppBar(title: const Text('Dev Firestore Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'app=$appName\nprojectId=$projectId\nemulator=${usesEmulator ? 'yes($host)' : 'no'}\nuid=$uid\nemail=${u?.email}\nanon=${u?.isAnonymous}\npaths: ${FirestorePaths.jobs} / ${FirestorePaths.cvs} / ${FirestorePaths.responses} / ${FirestorePaths.notifications}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (isProd)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                'Production environment detected. Destructive debug actions are disabled.',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
              ),
            ),
          if (isProd) const SizedBox(height: 8),
          if (uid.isNotEmpty)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: orphanCvsStream,
              builder: (context, snap) {
                final hasOrphans = (snap.data?.docs.isNotEmpty ?? false);
                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: (!isProd && hasOrphans)
                        ? () => _attachOrphanCvsToCurrentUser(context, uid)
                        : null,
                    child: Text(
                      hasOrphans
                          ? 'Attach orphan cvs to current uid (debug)'
                          : 'No orphan cvs found',
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          if (_cleaning)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cleaning || isProd
                    ? null
                    : () => _clearResponsesAndNotifications(context),
                child:
                    const Text('Очистить отклики/предложения (responses) + уведомления'),
              ),
            ),
          const SizedBox(height: 12),
          _block(
            title: 'CVS (root, no filter, limit 5)',
            stream: db.collection(FirestorePaths.cvs).limit(5).snapshots(),
          ),
          _block(
            title: 'CVS (root, ownerId == uid, limit 5)',
            stream: uid.isEmpty
                ? const Stream.empty()
                : db.collection(FirestorePaths.cvs).where('ownerId', isEqualTo: uid).limit(5).snapshots(),
          ),
          _block(
            title: 'Jobs (root, no filter, limit 5)',
            stream: db.collection(FirestorePaths.jobs).limit(5).snapshots(),
          ),
          _block(
            title: 'Jobs (root, ownerId == uid, limit 5)',
            stream: uid.isEmpty
                ? const Stream.empty()
                : db.collection(FirestorePaths.jobs).where('ownerId', isEqualTo: uid).limit(5).snapshots(),
          ),
        ],
      ),
    );
  }
}
