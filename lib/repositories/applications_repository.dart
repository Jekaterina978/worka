import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/interaction_models.dart';
import '../services/auth_guard.dart';
import '../services/entity_validity.dart';
import '../services/firestore_paths.dart';
import '../services/interaction_status.dart';

class ApplicationsRepository {
  ApplicationsRepository(this._db);

  final FirebaseFirestore _db;
  final Map<String, bool> _jobExistsCache = <String, bool>{};
  final Map<String, bool> _cvExistsCache = <String, bool>{};
  final Map<String, String> _jobOwnerCache = <String, String>{};
  final Map<String, String> _cvOwnerCache = <String, String>{};

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.applications);

  bool _isSoftDeleted(Map<String, dynamic> m) => m['isDeleted'] == true;
  String _applyEmployerOwnerId(Map<String, dynamic> m) {
    return (m['employerOwnerId'] ??
            m['vacancyOwnerId'] ??
            m['employerId'] ??
            m['employerUid'] ??
            m['vacancyOwnerKey'] ??
            '')
        .toString()
        .trim();
  }

  String _applyCandidateOwnerId(Map<String, dynamic> m) {
    return (m['candidateOwnerId'] ??
            m['candidateId'] ??
            m['candidateUid'] ??
            m['applicantId'] ??
            m['candidateOwnerKey'] ??
            '')
        .toString()
        .trim();
  }

  bool _hasRequiredLinks(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidResponse(m);
  }

  String _vacancyOwnerId(Map<String, dynamic> m) {
    return (m['ownerId'] ??
            m['ownerUid'] ??
            m['ownerKey'] ??
            m['vacancyOwnerId'] ??
            m['employerOwnerId'] ??
            '')
        .toString()
        .trim();
  }

  String _cvOwnerId(Map<String, dynamic> m) {
    return (m['ownerId'] ??
            m['ownerUid'] ??
            m['candidateOwnerId'] ??
            m['candidateId'] ??
            m['candidateUid'] ??
            '')
        .toString()
        .trim();
  }

  Future<bool> _docExists({
    required String collection,
    required String id,
    required Map<String, bool> cache,
  }) async {
    if (id.isEmpty) return false;
    final attempts = <String>[collection];
    if (collection == FirestorePaths.jobsTest) {
      attempts.add(FirestorePaths.jobs);
    } else if (collection == FirestorePaths.jobs) {
      attempts.add(FirestorePaths.jobsTest);
    } else if (collection == FirestorePaths.cvsTest) {
      attempts.add(FirestorePaths.cvs);
    } else if (collection == FirestorePaths.cvs) {
      attempts.add(FirestorePaths.cvsTest);
    }
    for (final col in attempts.toSet()) {
      final key = '$col/$id';
      final cached = cache[key];
      if (cached != null) {
        if (cached) return true;
        continue;
      }
      final snap = await _db.collection(col).doc(id).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final exists = snap.exists && data['isDeleted'] != true;
      cache[key] = exists;
      if (exists) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _loadLinkedDoc({
    required String collection,
    required String id,
  }) async {
    if (id.isEmpty) return const <String, dynamic>{};
    final attempts = <String>[collection];
    if (collection == FirestorePaths.jobsTest) {
      attempts.add(FirestorePaths.jobs);
    } else if (collection == FirestorePaths.jobs) {
      attempts.add(FirestorePaths.jobsTest);
    } else if (collection == FirestorePaths.cvsTest) {
      attempts.add(FirestorePaths.cvs);
    } else if (collection == FirestorePaths.cvs) {
      attempts.add(FirestorePaths.cvsTest);
    }
    for (final col in attempts.toSet()) {
      final snap = await _db.collection(col).doc(id).get();
      if (!snap.exists) continue;
      final data = snap.data() ?? const <String, dynamic>{};
      if (data['isDeleted'] == true) return const <String, dynamic>{};
      return data;
    }
    return const <String, dynamic>{};
  }

  Future<bool> _hasValidLinkedSources(
    Map<String, dynamic> m, {
    required bool testMode,
    String expectedVacancyOwnerId = '',
    String expectedCvOwnerId = '',
  }) async {
    if (!_hasRequiredLinks(m) || _isSoftDeleted(m)) return false;
    final jobId = (m['jobId'] ?? m['vacancyId'] ?? '').toString().trim();
    final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim();
    final jobsCol = FirestorePaths.jobsCol(testMode: testMode);
    final cvsCol = FirestorePaths.cvsCol(testMode: testMode);
    final hasJob = await _docExists(
      collection: jobsCol,
      id: jobId,
      cache: _jobExistsCache,
    );
    if (!hasJob) return false;
    final hasCv = await _docExists(
      collection: cvsCol,
      id: cvId,
      cache: _cvExistsCache,
    );
    if (!hasCv) return false;
    final linkedJob = await _loadLinkedDoc(collection: jobsCol, id: jobId);
    final linkedCv = await _loadLinkedDoc(collection: cvsCol, id: cvId);
    if (linkedJob.isEmpty || linkedCv.isEmpty) return false;
    if (!WorkaEntityValidity.isValidPublicVacancy(linkedJob)) return false;
    if (!WorkaEntityValidity.isValidPublicCv(linkedCv)) return false;
    if (expectedVacancyOwnerId.trim().isNotEmpty) {
      final owner = await _linkedDocOwnerId(
        collection: jobsCol,
        id: jobId,
        cache: _jobOwnerCache,
        isVacancy: true,
      );
      if (owner != expectedVacancyOwnerId.trim()) return false;
    }
    if (expectedCvOwnerId.trim().isNotEmpty) {
      final owner = await _linkedDocOwnerId(
        collection: cvsCol,
        id: cvId,
        cache: _cvOwnerCache,
        isVacancy: false,
      );
      if (owner != expectedCvOwnerId.trim()) return false;
    }
    return true;
  }

  Future<String> _linkedDocOwnerId({
    required String collection,
    required String id,
    required Map<String, String> cache,
    required bool isVacancy,
  }) async {
    if (id.isEmpty) return '';
    final attempts = <String>[collection];
    if (collection == FirestorePaths.jobsTest) {
      attempts.add(FirestorePaths.jobs);
    } else if (collection == FirestorePaths.jobs) {
      attempts.add(FirestorePaths.jobsTest);
    } else if (collection == FirestorePaths.cvsTest) {
      attempts.add(FirestorePaths.cvs);
    } else if (collection == FirestorePaths.cvs) {
      attempts.add(FirestorePaths.cvsTest);
    }
    for (final col in attempts.toSet()) {
      final key = '$col/$id';
      final cached = cache[key];
      if (cached != null) return cached;
      final snap = await _db.collection(col).doc(id).get();
      final data = snap.data() ?? const <String, dynamic>{};
      if (!snap.exists || data['isDeleted'] == true) {
        cache[key] = '';
        continue;
      }
      final owner = isVacancy ? _vacancyOwnerId(data) : _cvOwnerId(data);
      cache[key] = owner;
      if (owner.isNotEmpty) return owner;
    }
    return '';
  }

  Future<void> create({
    required String id,
    required ApplicationCreate payload,
    bool merge = true,
  }) async {
    final jobCode = payload.vacancyId.trim();
    final candidateId = payload.candidateId.trim();
    final message = '';
    if (jobCode.isEmpty || candidateId.isEmpty) {
      throw ArgumentError('jobCode and candidateId are required');
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для отправки отклика.');
    }
    const base = String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '');
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = Uri.parse('$normalizedBase/apply');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'jobCode': jobCode,
        'candidateId': candidateId,
        'message': message,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw StateError(
        'Не удалось отправить отклик: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchForEmployer({
    required String employerUid,
    required bool testMode,
    String vacancyId = '',
  }) {
    final uid = employerUid.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    debugPrint(
      'ApplicationsRepository.watchForEmployer '
      'collection=${FirestorePaths.applications} '
      'filters=[type=apply,employerOwnerId=$uid] '
      'orderBy=updatedAt(desc)',
    );
    return _col.snapshots().asyncMap((s) async {
      final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in s.docs) {
        final m = d.data();
        final type = (m['type'] ?? '').toString().trim().toLowerCase();
        if (type != 'apply') continue;
        if (_applyEmployerOwnerId(m) != uid) continue;
        if (vacancyId.trim().isNotEmpty) {
          final jobId = (m['jobId'] ?? m['vacancyId'] ?? '').toString().trim();
          if (jobId != vacancyId.trim()) continue;
        }
        if (!await _hasValidLinkedSources(
          m,
          testMode: testMode,
          expectedVacancyOwnerId: uid,
        )) {
          continue;
        }
        out.add(d);
      }
      out.sort((a, b) {
        final at = a.data()['updatedAt'];
        final bt = b.data()['updatedAt'];
        final ad = at is Timestamp
            ? at.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        final bd = bt is Timestamp
            ? bt.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return out;
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchForCandidate({
    required String candidateUid,
    required bool testMode,
  }) {
    final uid = candidateUid.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    debugPrint(
      'ApplicationsRepository.watchForCandidate '
      'collection=${FirestorePaths.applications} '
      'filters=[type=apply,candidateOwnerId=$uid] '
      'orderBy=updatedAt(desc)',
    );
    return _col.snapshots().asyncMap((s) async {
      final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in s.docs) {
        final m = d.data();
        final type = (m['type'] ?? '').toString().trim().toLowerCase();
        if (type != 'apply') continue;
        if (_applyCandidateOwnerId(m) != uid) continue;
        if (!await _hasValidLinkedSources(
          m,
          testMode: testMode,
          expectedCvOwnerId: uid,
        )) {
          continue;
        }
        out.add(d);
      }
      out.sort((a, b) {
        final at = a.data()['updatedAt'];
        final bt = b.data()['updatedAt'];
        final ad = at is Timestamp
            ? at.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        final bd = bt is Timestamp
            ? bt.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return out;
    });
  }

  Future<void> markViewed({
    required DocumentReference<Map<String, dynamic>> ref,
    required bool viewedByCandidate,
  }) async {
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? const <String, dynamic>{};
    final status = InteractionStatus.normalize(data['status']);
    final patch = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == InteractionStatus.pending)
        'status': InteractionStatus.viewed,
      if (viewedByCandidate) 'statusCandidate': InteractionStatus.viewed,
      if (!viewedByCandidate) 'statusEmployer': InteractionStatus.viewed,
      'isNew': false,
      if (viewedByCandidate) 'unreadForCandidate': false,
      if (!viewedByCandidate) 'unreadForEmployer': false,
    };
    await ref.update(patch);
  }

  Future<void> markAllReadForEmployer({
    required String employerId,
    required bool testMode,
  }) async {
    final snap = await _col.snapshots().first;
    for (final d in snap.docs) {
      final m = d.data();
      if (_isSoftDeleted(m)) continue;
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'apply') continue;
      final owner = (m['employerOwnerId'] ?? '').toString().trim();
      if (owner != employerId.trim()) continue;
      if ((m['unreadForEmployer'] ?? false) != true) continue;
      final status = InteractionStatus.normalize(
        m['statusEmployer'] ?? m['status'],
      );
      await d.reference.update({
        'isNew': false,
        'unreadForEmployer': false,
        if (InteractionStatus.isFresh(status))
          'statusEmployer': InteractionStatus.viewed,
        if (InteractionStatus.isFresh(status))
          'status': InteractionStatus.viewed,
        'viewedByEmployerAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> markAllReadForCandidate({
    required String candidateId,
    required bool testMode,
  }) async {
    final snap = await _col.snapshots().first;
    for (final d in snap.docs) {
      final m = d.data();
      if (_isSoftDeleted(m)) continue;
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'apply') continue;
      final owner = (m['candidateOwnerId'] ?? '').toString().trim();
      if (owner != candidateId.trim()) continue;
      if ((m['unreadForCandidate'] ?? false) != true) continue;
      final status = InteractionStatus.normalize(
        m['statusCandidate'] ?? m['status'],
      );
      await d.reference.update({
        'isNew': false,
        'unreadForCandidate': false,
        if (InteractionStatus.isFresh(status))
          'statusCandidate': InteractionStatus.viewed,
        if (InteractionStatus.isFresh(status))
          'status': InteractionStatus.viewed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<bool> existsDuplicate({
    required String candidateId,
    required String cvId,
    required String vacancyId,
  }) async {
    final docs =
        (await _col
                .where('type', isEqualTo: 'apply')
                .where('candidateOwnerId', isEqualTo: candidateId)
                .get())
            .docs;
    for (final d in docs) {
      final m = d.data();
      if (_isSoftDeleted(m)) continue;
      if (!_hasRequiredLinks(m)) continue;
      if ((m['candidateCvId'] ?? '').toString().trim() != cvId.trim()) continue;
      final v = (m['jobId'] ?? '').toString().trim();
      if (v != vacancyId.trim()) continue;
      final status = (m['status'] ?? '').toString().trim().toLowerCase();
      if (const {'sent', 'viewed', 'accepted', 'rejected'}.contains(status)) {
        return true;
      }
    }
    return false;
  }

  Stream<Set<String>> watchAppliedJobIdsForCandidate({
    required String candidateUid,
  }) {
    debugPrint(
      'ApplicationsRepository.watchAppliedJobIdsForCandidate '
      'uid=$candidateUid filter=type:apply+candidateOwnerId+jobId',
    );
    if (candidateUid.trim().isEmpty) return Stream.value(<String>{});

    return _col
        .where('type', isEqualTo: 'apply')
        .where('candidateOwnerId', isEqualTo: candidateUid.trim())
        .snapshots()
        .map((s) {
          final out = <String>{};
          for (final d in s.docs) {
            final m = d.data();
            if (_isSoftDeleted(m)) continue;
            if (!_hasRequiredLinks(m)) continue;
            final jobId = (m['jobId'] ?? '').toString().trim();
            if (jobId.isEmpty) continue;
            out.add(jobId);
          }
          return out;
        });
  }

  Stream<bool> hasAppliedToVacancy({
    required String applicantId,
    required String vacancyId,
  }) {
    final uid = applicantId.trim();
    final jobId = vacancyId.trim();
    if (uid.isEmpty || jobId.isEmpty) return Stream.value(false);
    return _col
        .where('applicantId', isEqualTo: uid)
        .where('vacancyId', isEqualTo: jobId)
        .where(
          'status',
          whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
        )
        .limit(10)
        .snapshots()
        .map(
          (s) => s.docs.any((d) {
            final m = d.data();
            return !_isSoftDeleted(m) && _hasRequiredLinks(m);
          }),
        )
        .distinct();
  }
}
