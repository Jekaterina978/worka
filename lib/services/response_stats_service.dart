import 'package:cloud_firestore/cloud_firestore.dart';

import 'entity_validity.dart';
import 'firestore_paths.dart';
import 'interaction_status.dart';

class ResponseStats {
  final int fresh;
  final int total;

  const ResponseStats({required this.fresh, required this.total});
}

class ResponseStatsService {
  ResponseStatsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final Map<String, bool> _jobExistsCache = <String, bool>{};
  static final Map<String, bool> _cvExistsCache = <String, bool>{};
  static final Map<String, String> _jobOwnerCache = <String, String>{};
  static final Map<String, String> _cvOwnerCache = <String, String>{};

  static void clearCaches() {
    _jobExistsCache.clear();
    _cvExistsCache.clear();
    _jobOwnerCache.clear();
    _cvOwnerCache.clear();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _applicationsStream() {
    return _db.collection(FirestorePaths.applications).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _offersStream() {
    return _db.collection(FirestorePaths.jobOffers).snapshots();
  }

  static bool _isApply(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidResponse(m);
  }

  static bool _isOffer(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidOffer(m);
  }

  static bool _isFreshByStatus(
    Map<String, dynamic> m, {
    required bool forEmployer,
  }) {
    final unreadFlag = forEmployer
        ? m['unreadForEmployer']
        : m['unreadForCandidate'];
    if (unreadFlag is bool) return unreadFlag;
    final sideStatus = forEmployer
        ? (m['statusEmployer'] ?? m['status'])
        : (m['statusCandidate'] ?? m['status']);
    return InteractionStatus.isFresh(sideStatus);
  }

  static String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  static String _applyEmployerOwnerId(Map<String, dynamic> m) {
    return _s(
      m['employerOwnerId'],
      fallback: _s(
        m['vacancyOwnerId'],
        fallback: _s(
          m['employerId'],
          fallback: _s(m['employerUid'], fallback: _s(m['vacancyOwnerKey'])),
        ),
      ),
    );
  }

  static String _applyCandidateOwnerId(Map<String, dynamic> m) {
    return _s(
      m['candidateOwnerId'],
      fallback: _s(
        m['candidateId'],
        fallback: _s(
          m['candidateUid'],
          fallback: _s(m['applicantId'], fallback: _s(m['candidateOwnerKey'])),
        ),
      ),
    );
  }

  static String _offerEmployerOwnerId(Map<String, dynamic> m) {
    return _s(
      m['employerOwnerId'],
      fallback: _s(
        m['vacancyOwnerId'],
        fallback: _s(
          m['employerId'],
          fallback: _s(m['employerUid'], fallback: _s(m['vacancyOwnerKey'])),
        ),
      ),
    );
  }

  static String _offerCandidateOwnerId(Map<String, dynamic> m) {
    return _s(
      m['candidateOwnerId'],
      fallback: _s(
        m['candidateId'],
        fallback: _s(m['candidateUid'], fallback: _s(m['candidateOwnerKey'])),
      ),
    );
  }

  static Future<bool> _docExists({
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

  static Future<bool> _hasRequiredLinks(
    Map<String, dynamic> m, {
    required bool testMode,
    required bool requireJob,
    required bool requireCv,
    String expectedVacancyOwnerId = '',
    String expectedCvOwnerId = '',
  }) async {
    if (m['isDeleted'] == true) return false;
    final jobId = _s(m['jobId']).isNotEmpty
        ? _s(m['jobId'])
        : _s(m['vacancyId']);
    final cvId = _s(m['candidateCvId']).isNotEmpty
        ? _s(m['candidateCvId'])
        : _s(m['cvId']);
    if (jobId.isEmpty || cvId.isEmpty) return false;

    final jobsCol = FirestorePaths.jobsCol(testMode: testMode);
    final cvsCol = FirestorePaths.cvsCol(testMode: testMode);

    if (requireJob &&
        !await _docExists(
          collection: jobsCol,
          id: jobId,
          cache: _jobExistsCache,
        )) {
      return false;
    }
    if (requireCv &&
        !await _docExists(
          collection: cvsCol,
          id: cvId,
          cache: _cvExistsCache,
        )) {
      return false;
    }
    final linkedJob = await _loadLinkedDoc(collection: jobsCol, id: jobId);
    final linkedCv = await _loadLinkedDoc(collection: cvsCol, id: cvId);
    if (linkedJob.isEmpty || linkedCv.isEmpty) return false;
    if (!WorkaEntityValidity.isValidPublicVacancy(linkedJob)) return false;
    if (!WorkaEntityValidity.isValidPublicCv(linkedCv)) return false;
    if (expectedVacancyOwnerId.trim().isNotEmpty) {
      final linkedOwner = await _linkedDocOwnerId(
        collection: jobsCol,
        id: jobId,
        cache: _jobOwnerCache,
        isVacancy: true,
      );
      if (linkedOwner != expectedVacancyOwnerId.trim()) return false;
    }
    if (expectedCvOwnerId.trim().isNotEmpty) {
      final linkedOwner = await _linkedDocOwnerId(
        collection: cvsCol,
        id: cvId,
        cache: _cvOwnerCache,
        isVacancy: false,
      );
      if (linkedOwner != expectedCvOwnerId.trim()) return false;
    }
    return true;
  }

  static Future<Map<String, dynamic>> _loadLinkedDoc({
    required String collection,
    required String id,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return const <String, dynamic>{};
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
      final snap = await _db.collection(col).doc(cleanId).get();
      if (!snap.exists) continue;
      final data = snap.data() ?? const <String, dynamic>{};
      if (data['isDeleted'] == true) return const <String, dynamic>{};
      return data;
    }
    return const <String, dynamic>{};
  }

  static String _vacancyOwnerId(Map<String, dynamic> m) {
    return _s(
      m['ownerId'],
      fallback: _s(
        m['ownerUid'],
        fallback: _s(
          m['ownerKey'],
          fallback: _s(m['vacancyOwnerId'], fallback: _s(m['employerOwnerId'])),
        ),
      ),
    );
  }

  static String _cvOwnerId(Map<String, dynamic> m) {
    return _s(
      m['ownerId'],
      fallback: _s(
        m['ownerUid'],
        fallback: _s(
          m['candidateOwnerId'],
          fallback: _s(m['candidateId'], fallback: _s(m['candidateUid'])),
        ),
      ),
    );
  }

  static Future<String> _linkedDocOwnerId({
    required String collection,
    required String id,
    required Map<String, String> cache,
    required bool isVacancy,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return '';
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
      final key = '$col/$cleanId';
      final cached = cache[key];
      if (cached != null) return cached;
      final snap = await _db.collection(col).doc(cleanId).get();
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

  static String _dedupeKey(Map<String, dynamic> m) {
    final type = _s(m['type']).toLowerCase();
    final jobId = _s(m['jobId']).isNotEmpty
        ? _s(m['jobId'])
        : _s(m['vacancyId']);
    final cvId = _s(m['candidateCvId']).isNotEmpty
        ? _s(m['candidateCvId'])
        : _s(m['cvId']);
    final candidateOwner = _isApply(m)
        ? _applyCandidateOwnerId(m)
        : _offerCandidateOwnerId(m);
    final employerOwner = _isApply(m)
        ? _applyEmployerOwnerId(m)
        : _offerEmployerOwnerId(m);
    if (type == 'apply') return 'apply|$jobId|$candidateOwner|$cvId';
    if (type == 'offer') return 'offer|$jobId|$employerOwner|$cvId';
    return '$type|$jobId|$candidateOwner|$employerOwner|$cvId';
  }

  static Stream<ResponseStats> watchEmployerApplicationsStats(
    String employerUid, {
    bool testMode = false,
  }) {
    return _applicationsStream().asyncMap((snap) async {
      final docs = snap.docs.where((d) {
        final m = d.data();
        if (!_isApply(m)) return false;
        final employerId =
            (m['employerOwnerId'] ??
                    m['vacancyOwnerId'] ??
                    m['employerId'] ??
                    m['employerUid'] ??
                    m['vacancyOwnerKey'] ??
                    '')
                .toString()
                .trim();
        return employerId == employerUid;
      }).toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
          expectedVacancyOwnerId: employerUid,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: true)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchEmployerOffersSentStats(
    String employerUid, {
    bool testMode = false,
  }) {
    return _offersStream().asyncMap((snap) async {
      final docs = snap.docs.where((d) {
        final m = d.data();
        if (!_isOffer(m)) return false;
        final employerId = _offerEmployerOwnerId(m);
        return employerId == employerUid;
      }).toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
          expectedVacancyOwnerId: employerUid,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: true)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchCandidateOffersStats(
    String candidateUid, {
    bool testMode = false,
  }) {
    return _offersStream().asyncMap((snap) async {
      final docs = snap.docs.where((d) {
        final m = d.data();
        if (!_isOffer(m)) return false;
        final candidateId = _offerCandidateOwnerId(m);
        return candidateId == candidateUid;
      }).toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
          expectedCvOwnerId: candidateUid,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: false)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchCandidateApplicationsStats(
    String candidateUid, {
    bool testMode = false,
  }) {
    return _applicationsStream().asyncMap((snap) async {
      final docs = snap.docs.where((d) {
        final m = d.data();
        if (!_isApply(m)) return false;
        final candidateId = _applyCandidateOwnerId(m);
        return candidateId == candidateUid;
      }).toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
          expectedCvOwnerId: candidateUid,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: false)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchJobApplicationsStats(
    String jobId, {
    bool testMode = false,
  }) {
    return _applicationsStream().asyncMap((snap) async {
      final docs = snap.docs.where((d) {
        final m = d.data();
        if (!_isApply(m)) return false;
        final vacancyId = (m['vacancyId'] ?? m['jobId'] ?? '')
            .toString()
            .trim();
        return vacancyId == jobId;
      }).toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: true)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchCandidateOffersStatsForCard(
    String candidateUid, {
    bool testMode = false,
  }) {
    return watchCandidateOffersStats(candidateUid, testMode: testMode);
  }

  static Stream<ResponseStats> watchAllTestCandidateOffersStats() {
    return _offersStream().asyncMap((snap) async {
      final docs = snap.docs
          .where(
            (d) => _isOffer(d.data()) && (d.data()['test'] ?? false) == true,
          )
          .toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: true,
          requireJob: true,
          requireCv: true,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: false)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<ResponseStats> watchAllTestEmployerApplicationsStats() {
    return _applicationsStream().asyncMap((snap) async {
      final docs = snap.docs
          .where(
            (d) => _isApply(d.data()) && (d.data()['test'] ?? false) == true,
          )
          .toList();
      int total = 0;
      int fresh = 0;
      final seen = <String>{};
      for (final d in docs) {
        final m = d.data();
        if (!await _hasRequiredLinks(
          m,
          testMode: true,
          requireJob: true,
          requireCv: true,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        total += 1;
        if (_isFreshByStatus(m, forEmployer: true)) fresh += 1;
      }
      return ResponseStats(fresh: fresh, total: total);
    });
  }

  static Stream<Map<String, ResponseStats>>
  watchEmployerApplicationsGroupedByJob(
    String employerUid, {
    bool testMode = false,
  }) {
    return _applicationsStream().asyncMap((snap) async {
      final out = <String, ResponseStats>{};
      final mutable = <String, List<int>>{};
      final seen = <String>{};
      for (final d in snap.docs) {
        final m = d.data();
        if (!_isApply(m)) continue;
        if (!await _hasRequiredLinks(
          m,
          testMode: testMode,
          requireJob: true,
          requireCv: true,
          expectedVacancyOwnerId: employerUid,
        )) {
          continue;
        }
        final key = _dedupeKey(m);
        if (!seen.add(key)) continue;
        final employerId = _applyEmployerOwnerId(m);
        if (employerId != employerUid) continue;
        final vacancyId = (m['vacancyId'] ?? m['jobId'] ?? '')
            .toString()
            .trim();
        if (vacancyId.isEmpty) continue;
        final pair = mutable.putIfAbsent(vacancyId, () => <int>[0, 0]);
        if (_isFreshByStatus(m, forEmployer: true)) pair[0] = pair[0] + 1;
        pair[1] = pair[1] + 1;
      }
      mutable.forEach((vacancyId, p) {
        out[vacancyId] = ResponseStats(fresh: p[0], total: p[1]);
      });
      return out;
    });
  }
}
