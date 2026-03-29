import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/response_model.dart';
import '../data/models/interaction_models.dart';
import '../services/auth_guard.dart';
import '../services/firestore_paths.dart';
import 'applications_repository.dart';
import 'job_offers_repository.dart';

class ResponseRepository {
  ResponseRepository(this._db);

  final FirebaseFirestore _db;
  static const Set<String> _sensitiveCandidateContactKeys = <String>{
    'email',
    'phone',
    'phoneNumber',
    'phoneCountryCode',
    'whatsapp',
    'telegram',
    'viber',
    'messenger',
    'tg',
    'wa',
    'facebookMessenger',
    'contactEmail',
    'contactPhone',
    'candidateEmail',
    'candidatePhone',
    'candidateEmailSnapshot',
    'candidatePhoneSnapshot',
  };

  CollectionReference<Map<String, dynamic>> get _applicationsCol =>
      _db.collection(FirestorePaths.applications);
  CollectionReference<Map<String, dynamic>> get _offersCol =>
      _db.collection(FirestorePaths.jobOffers);

  Future<DocumentReference<Map<String, dynamic>>?> _resolveRefById(
    String id,
  ) async {
    final key = id.trim();
    if (key.isEmpty) return null;
    final refs = <DocumentReference<Map<String, dynamic>>>[
      _applicationsCol.doc(key),
      _offersCol.doc(key),
    ];
    for (final ref in refs) {
      final snap = await ref.get();
      if (snap.exists) return ref;
    }
    return null;
  }

  Future<void> _debugAssertRequiredFields(String responseId) async {
    if (!kDebugMode) return;
    try {
      final ref = await _resolveRefById(responseId);
      if (ref == null) return;
      final snap = await ref.get();
      if (!snap.exists) {
        debugPrint(
          '[ResponseIntegrityError] missing doc after status update: $responseId',
        );
        return;
      }
      final m = snap.data() ?? const <String, dynamic>{};
      final type = (m['type'] ?? '').toString().trim();
      final employer = (m['employerOwnerId'] ?? '').toString().trim();
      final candidate = (m['candidateOwnerId'] ?? '').toString().trim();
      final jobId = (m['jobId'] ?? '').toString().trim();
      if (type.isEmpty ||
          employer.isEmpty ||
          candidate.isEmpty ||
          jobId.isEmpty) {
        debugPrint(
          '[ResponseIntegrityError] required fields lost after status update responseId=$responseId '
          'type="$type" employerOwnerId="$employer" candidateOwnerId="$candidate" jobId="$jobId"',
        );
      }
    } catch (e) {
      debugPrint('[ResponseIntegrityError] check failed for $responseId: $e');
    }
  }

  Map<String, dynamic> _sanitizeCandidateSnapshot(
    Map<String, dynamic> raw,
  ) {
    final out = Map<String, dynamic>.from(raw);
    for (final key in _sensitiveCandidateContactKeys) {
      out.remove(key);
    }
    final contacts = out['contacts'];
    if (contacts is Map) {
      final sanitizedContacts = Map<String, dynamic>.from(contacts);
      for (final key in _sensitiveCandidateContactKeys) {
        sanitizedContacts.remove(key);
      }
      out['contacts'] = sanitizedContacts;
    }
    return out;
  }

  // Firestore composite indexes expected:
  // 1) employerOwnerId + type + createdAt(desc)
  // 2) candidateOwnerId + type + createdAt(desc)
  // 3) jobId + candidateOwnerId + type

  Future<void> createApply({
    required String jobId,
    required String jobOwnerId,
    required String candidateCvId,
    required String candidateOwnerId,
    // Snapshot fields — stored at send time for letter display resilience.
    String vacancyOwnerType = 'personal',
    String applicantProfileType = 'personal',
    String applicantNameSnapshot = '',
    String applicantEmailSnapshot = '',
    String applicantPhoneSnapshot = '',
    String cvTitleSnapshot = '',
    String cvLocationSnapshot = '',
    String cvCategorySnapshot = '',
    List<String> cvSkillsSnapshot = const [],
    Map<String, dynamic> vacancySnapshot = const {},
    Map<String, dynamic> candidateSnapshot = const {},
  }) async {
    final safeJobId = jobId.trim();
    final safeJobOwnerId = jobOwnerId.trim();
    final safeCandidateId = candidateOwnerId.trim();
    final safeCvId = candidateCvId.trim();
    if (safeJobId.isEmpty ||
        safeJobOwnerId.isEmpty ||
        safeCandidateId.isEmpty) {
      throw ArgumentError('createApply requires non-empty ids');
    }
    if (AuthGuard.isGuestLikeUid(safeJobOwnerId) ||
        AuthGuard.isGuestLikeUid(safeCandidateId)) {
      throw ArgumentError(
        'createApply requires authenticated non-guest owner ids',
      );
    }

    final responseId = <String>[
      'apply',
      safeJobId,
      safeCandidateId,
      safeJobOwnerId,
    ].join('_').replaceAll('/', '_');
    final exists = await ApplicationsRepository(_db).existsDuplicate(
      candidateId: safeCandidateId,
      cvId: safeCvId,
      vacancyId: safeJobId,
    );
    if (exists) return;

    try {
      await ApplicationsRepository(_db).create(
        id: responseId,
        payload: ApplicationCreate(
          vacancyId: safeJobId,
          vacancyOwnerId: safeJobOwnerId,
          vacancyOwnerType: vacancyOwnerType,
          candidateId: safeCandidateId,
          cvId: safeCvId,
          applicantProfileType: applicantProfileType,
          applicantNameSnapshot: applicantNameSnapshot,
          applicantEmailSnapshot: '',
          applicantPhoneSnapshot: '',
          cvTitleSnapshot: cvTitleSnapshot,
          cvLocationSnapshot: cvLocationSnapshot,
          cvCategorySnapshot: cvCategorySnapshot,
          cvSkillsSnapshot: cvSkillsSnapshot,
          vacancySnapshot: vacancySnapshot,
          candidateSnapshot: _sanitizeCandidateSnapshot(candidateSnapshot),
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'already-exists') return;
      rethrow;
    }
  }

  Future<void> createOffer({
    required String candidateOwnerId,
    required String candidateCvId,
    required String employerOwnerId,
    required String jobId,
    required String jobOwnerId,
    // Snapshot fields — stored at send time for letter display resilience.
    String vacancyOwnerType = 'personal',
    String employerType = 'personal',
    String recipientProfileType = 'personal',
    String cvTitleSnapshot = '',
    String cvLocationSnapshot = '',
    String cvCategorySnapshot = '',
    List<String> cvSkillsSnapshot = const [],
    String candidateNameSnapshot = '',
    String candidateEmailSnapshot = '',
    String candidatePhoneSnapshot = '',
    Map<String, dynamic> vacancySnapshot = const {},
    Map<String, dynamic> candidateSnapshot = const {},
    Map<String, dynamic> employerContactsSnapshot = const {},
  }) async {
    final safeCandidateId = candidateOwnerId.trim();
    final safeCvId = candidateCvId.trim();
    final safeEmployerId = employerOwnerId.trim();
    final safeJobId = jobId.trim();
    final safeJobOwnerId = jobOwnerId.trim();
    if (safeCandidateId.isEmpty ||
        safeEmployerId.isEmpty ||
        safeJobId.isEmpty ||
        safeJobOwnerId.isEmpty) {
      throw ArgumentError(
        'createOffer requires non-empty candidate/cv/employer/job ids',
      );
    }
    if (AuthGuard.isGuestLikeUid(safeCandidateId) ||
        AuthGuard.isGuestLikeUid(safeEmployerId) ||
        AuthGuard.isGuestLikeUid(safeJobOwnerId)) {
      throw ArgumentError(
        'createOffer requires authenticated non-guest owner ids',
      );
    }
    if (safeEmployerId != safeJobOwnerId) {
      throw ArgumentError('createOffer requires employerOwnerId == jobOwnerId');
    }

    final offerId = <String>[
      'offer',
      safeEmployerId,
      safeJobId,
      safeCandidateId,
    ].join('_').replaceAll('/', '_');
    final exists = await JobOffersRepository(_db).existsDuplicate(
      employerId: safeEmployerId,
      vacancyId: safeJobId,
      candidateId: safeCandidateId,
      cvId: safeCvId,
    );
    if (exists) return;

    try {
      await JobOffersRepository(_db).create(
        id: offerId,
        payload: OfferCreate(
          vacancyId: safeJobId,
          vacancyOwnerId: safeJobOwnerId,
          vacancyOwnerType: vacancyOwnerType,
          candidateId: safeCandidateId,
          cvId: safeCvId,
          employerType: employerType,
          recipientProfileType: recipientProfileType,
          cvTitleSnapshot: cvTitleSnapshot,
          cvLocationSnapshot: cvLocationSnapshot,
          cvCategorySnapshot: cvCategorySnapshot,
          cvSkillsSnapshot: cvSkillsSnapshot,
          candidateNameSnapshot: candidateNameSnapshot,
          candidateEmailSnapshot: '',
          candidatePhoneSnapshot: '',
          vacancySnapshot: vacancySnapshot,
          candidateSnapshot: _sanitizeCandidateSnapshot(candidateSnapshot),
          employerContactsSnapshot: employerContactsSnapshot,
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'already-exists') return;
      rethrow;
    }
  }

  Stream<bool> hasAppliedStream({
    required String jobId,
    required String candidateOwnerId,
    String candidateCvId = '',
  }) {
    final jid = jobId.trim();
    final uid = candidateOwnerId.trim();
    if (jid.isEmpty || uid.isEmpty) return Stream.value(false);
    final cv = candidateCvId.trim();
    var query = _db
        .collection(FirestorePaths.applications)
        .where('type', isEqualTo: 'apply')
        .where('jobId', isEqualTo: jid)
        .where('candidateOwnerId', isEqualTo: uid);
    if (cv.isNotEmpty) {
      query = query.where('candidateCvId', isEqualTo: cv);
    }
    return query
        .where(
          'status',
          whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
        )
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty)
        .distinct();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  candidateAppliesStream({required String candidateOwnerId}) {
    final uid = candidateOwnerId.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    return _applicationsCol
        .where('type', isEqualTo: ResponseType.apply.wire)
        .where('candidateOwnerId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  employerAppliesStream({required String employerOwnerId}) {
    final uid = employerOwnerId.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    return _applicationsCol
        .where('type', isEqualTo: ResponseType.apply.wire)
        .where('employerOwnerId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  candidateOffersStream({required String candidateOwnerId}) {
    final uid = candidateOwnerId.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    return _offersCol
        .where('type', isEqualTo: ResponseType.offer.wire)
        .where('candidateOwnerId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  employerOffersStream({required String employerOwnerId}) {
    final uid = employerOwnerId.trim();
    if (uid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    return _offersCol
        .where('type', isEqualTo: ResponseType.offer.wire)
        .where('employerOwnerId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Future<bool> hasAppliedOnce({
    required String jobId,
    required String candidateOwnerId,
    String candidateCvId = '',
  }) async {
    final jid = jobId.trim();
    final uid = candidateOwnerId.trim();
    if (jid.isEmpty || uid.isEmpty) return false;
    final cv = candidateCvId.trim();
    var newQuery = _db
        .collection(FirestorePaths.applications)
        .where('type', isEqualTo: 'apply')
        .where('jobId', isEqualTo: jid)
        .where('candidateOwnerId', isEqualTo: uid);
    if (cv.isNotEmpty) {
      newQuery = newQuery.where('candidateCvId', isEqualTo: cv);
    }
    final newSnap = await newQuery
        .where(
          'status',
          whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
        )
        .limit(1)
        .get();
    return newSnap.docs.isNotEmpty;
  }

  Stream<bool> hasOfferedStream({
    required String jobId,
    required String candidateOwnerId,
    String candidateCvId = '',
    String employerOwnerId = '',
  }) {
    final jid = jobId.trim();
    final uid = candidateOwnerId.trim();
    final cv = candidateCvId.trim();
    final employer = employerOwnerId.trim();
    if (jid.isEmpty || uid.isEmpty) return Stream.value(false);
    var query = _db
        .collection(FirestorePaths.jobOffers)
        .where('vacancyId', isEqualTo: jid)
        .where('candidateId', isEqualTo: uid);
    if (cv.isNotEmpty) {
      query = query.where('cvId', isEqualTo: cv);
    }
    if (employer.isNotEmpty) {
      query = query.where('employerId', isEqualTo: employer);
    }
    return query
        .where(
          'status',
          whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
        )
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty)
        .distinct();
  }

  Future<bool> hasOfferedOnce({
    required String jobId,
    required String candidateOwnerId,
    String candidateCvId = '',
    String employerOwnerId = '',
  }) async {
    final jid = jobId.trim();
    final uid = candidateOwnerId.trim();
    final cv = candidateCvId.trim();
    final employer = employerOwnerId.trim();
    if (jid.isEmpty || uid.isEmpty) return false;
    var newQuery = _db
        .collection(FirestorePaths.jobOffers)
        .where('vacancyId', isEqualTo: jid)
        .where('candidateId', isEqualTo: uid);
    if (employer.isNotEmpty) {
      newQuery = newQuery.where('employerId', isEqualTo: employer);
    }
    if (cv.isNotEmpty) {
      newQuery = newQuery.where('cvId', isEqualTo: cv);
    }
    final newSnap = await newQuery.limit(1).get();
    return newSnap.docs.isNotEmpty;
  }

  Stream<bool> hasResponseStream({
    required String type,
    required String jobId,
    required String candidateOwnerId,
    required String candidateCvId,
  }) {
    final t = type.trim().toLowerCase();
    if (t == ResponseType.apply.wire) {
      return hasAppliedStream(
        jobId: jobId,
        candidateOwnerId: candidateOwnerId,
        candidateCvId: candidateCvId,
      );
    }
    if (t == ResponseType.offer.wire) {
      return hasOfferedStream(
        jobId: jobId,
        candidateOwnerId: candidateOwnerId,
        candidateCvId: candidateCvId,
      );
    }
    return Stream.value(false);
  }

  Future<void> markViewedIfSent({
    required String responseId,
    required String viewerUid,
  }) async {
    final rid = responseId.trim();
    final uid = viewerUid.trim();
    if (rid.isEmpty || uid.isEmpty) return;
    final ref = await _resolveRefById(rid);
    if (ref == null) return;
    var updated = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final m = snap.data() ?? const <String, dynamic>{};
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      final status = (m['status'] ?? '').toString().trim().toLowerCase();
      if (kDebugMode) {
        debugPrint(
          '[markViewedIfSent][before] id=$rid type="$type" '
          'employerOwnerId="${(m['employerOwnerId'] ?? '').toString().trim()}" '
          'employerId="${(m['employerId'] ?? '').toString().trim()}" '
          'candidateOwnerId="${(m['candidateOwnerId'] ?? '').toString().trim()}" '
          'jobId="${(m['jobId'] ?? '').toString().trim()}" status="$status"',
        );
      }
      if (status != ResponseStatus.sent.wire) return;
      if (type == ResponseType.apply.wire) {
        final employerOwnerId = (m['employerOwnerId'] ?? '').toString().trim();
        final employerId = (m['employerId'] ?? '').toString().trim();
        final matches = employerOwnerId == uid || employerId == uid;
        if (!matches) return;
      } else {
        final candidateOwnerId = (m['candidateOwnerId'] ?? '')
            .toString()
            .trim();
        if (candidateOwnerId != uid) return;
      }
      tx.update(ref, {'status': ResponseStatus.viewed.wire});
      updated = true;
    });
    if (updated) {
      if (kDebugMode) {
        final after = await ref.get();
        final m = after.data() ?? const <String, dynamic>{};
        debugPrint(
          '[markViewedIfSent][after] id=$rid type="${(m['type'] ?? '').toString().trim()}" '
          'employerOwnerId="${(m['employerOwnerId'] ?? '').toString().trim()}" '
          'employerId="${(m['employerId'] ?? '').toString().trim()}" '
          'candidateOwnerId="${(m['candidateOwnerId'] ?? '').toString().trim()}" '
          'jobId="${(m['jobId'] ?? '').toString().trim()}" '
          'status="${(m['status'] ?? '').toString().trim()}"',
        );
      }
      await _debugAssertRequiredFields(rid);
    }
  }

  Future<void> updateStatus({
    required String responseId,
    required ResponseStatus newStatus,
    String actorUid = '',
  }) async {
    final rid = responseId.trim();
    if (rid.isEmpty) return;
    final actor = actorUid.trim();
    final ref = await _resolveRefById(rid);
    if (ref == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'Response not found',
      );
    }
    var updated = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Response not found',
        );
      }
      final data = snap.data() ?? const <String, dynamic>{};
      if (actor.isNotEmpty) {
        final type = (data['type'] ?? '').toString().trim().toLowerCase();
        final receiverUid = type == ResponseType.apply.wire
            ? (data['employerOwnerId'] ?? '').toString().trim()
            : (data['candidateOwnerId'] ?? '').toString().trim();
        if (receiverUid != actor) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Only recipient can change status',
          );
        }
      }
      tx.update(ref, {
        'status': newStatus.wire,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      updated = true;
    });
    if (updated) {
      await _debugAssertRequiredFields(rid);
    }
  }

  Future<void> accept({required String responseId, String actorUid = ''}) {
    return updateStatus(
      responseId: responseId,
      newStatus: ResponseStatus.accepted,
      actorUid: actorUid,
    );
  }

  Future<void> reject({required String responseId, String actorUid = ''}) {
    return updateStatus(
      responseId: responseId,
      newStatus: ResponseStatus.rejected,
      actorUid: actorUid,
    );
  }
}
