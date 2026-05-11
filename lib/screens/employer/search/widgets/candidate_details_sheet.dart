import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_contacts_section.dart'
    as contacts;
import 'package:worka/screens/employer/search/widgets/candidate_details_cv_sections.dart'
    as cv;
import 'package:worka/screens/employer/search/widgets/candidate_details_header_sections.dart'
    as header;
import 'package:worka/screens/employer/search/widgets/candidate_details_route_coordinator.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_ui_log_once.dart';
import 'package:worka/screens/employer/search/widgets/offer_job_picker_sheet.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/navigation_return_snapshot.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/ownership_context.dart';
import 'package:worka/services/candidate_identity_resolver.dart';
import 'package:worka/services/runtime_flow_logger.dart';
import 'package:worka/widgets/candidate_offer_sent_badge.dart'
    show mapJobOffersDocsToCardUi;
import 'package:worka/theme/worka_colors.dart';
enum CandidateDetailsUiState { locked, unlockTransition, unlocked }

class CandidateDetailsSheet extends StatefulWidget {
  static String buildDetailsGuardKey({
    required String candidateId,
    required String candidateUid,
    String? canonicalCandidateId,
  }) =>
      CandidateDetailsRouteCoordinator.buildDetailsGuardKey(
        candidateId: candidateId,
        candidateUid: candidateUid,
        canonicalCandidateId: canonicalCandidateId,
      );

  static bool get activeCandidateDetailsRouteOpen =>
      CandidateDetailsRouteCoordinator.activeCandidateDetailsRouteOpen;

  static String? get activeCandidateDetailsKey =>
      CandidateDetailsRouteCoordinator.activeCandidateDetailsKey;

  static bool isDetailsGuardKeyActive(String guardKey) =>
      CandidateDetailsRouteCoordinator.isDetailsGuardKeyActive(guardKey);

  static bool isDetailsGuardKeyOpeningInFlight(String guardKey) =>
      CandidateDetailsRouteCoordinator.isDetailsGuardKeyOpeningInFlight(
        guardKey,
      );

  static bool isDetailsGuardKeyActiveOrOpening(String guardKey) =>
      CandidateDetailsRouteCoordinator.isDetailsGuardKeyActiveOrOpening(
        guardKey,
      );

  final String candidateId;
  final String candidateUid;
  final String? canonicalCandidateId;
  final bool testMode;

  CandidateDetailsSheet({
    super.key,
    required this.candidateId,
    required this.candidateUid,
    this.canonicalCandidateId,
    this.testMode = false,
  }) : assert(
         !candidateId.contains('-'),
         'candidateId must be CV id, not canonical',
       ),
       assert(candidateUid.isNotEmpty, 'candidateUid missing'),
       assert(
         canonicalCandidateId == null || _isUuid(canonicalCandidateId),
         'canonicalCandidateId must be UUID when present',
       );

  static bool _isUuid(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  static Future<void> open(
    BuildContext context, {
    required String candidateId,
    required String candidateUid,
    String? canonicalCandidateId,
    bool testMode = false,
  }) async {
    final rawCanonical = (canonicalCandidateId ?? '').trim();
    final normalizedCanonical =
        CandidateIdentityResolver.normalizeCanonicalCandidateId(rawCanonical);
    RuntimeFlowLogger.mark('CANDIDATE_ID_RESOLVE', <String, Object?>{
      'source': 'candidate_details_sheet.open',
      'rawCandidateId': candidateId.trim(),
      'canonicalCandidateId': normalizedCanonical,
      'cvId': candidateId.trim(),
      'candidateOwnerId': candidateUid.trim(),
      'isCanonicalUuid': normalizedCanonical.isNotEmpty,
      if (rawCanonical.isNotEmpty) 'rawCanonicalCandidateId': rawCanonical,
    });
    final guardKey = buildDetailsGuardKey(
      candidateId: candidateId,
      candidateUid: candidateUid,
      canonicalCandidateId: normalizedCanonical.isNotEmpty
          ? normalizedCanonical
          : null,
    );

    await CandidateDetailsRouteCoordinator.openWhenAllowed(
      context: context,
      guardKey: guardKey,
      candidateId: candidateId.trim(),
      candidateUid: candidateUid.trim(),
      sheetContent: CandidateDetailsSheet(
        candidateId: candidateId.trim(),
        candidateUid: candidateUid.trim(),
        canonicalCandidateId: normalizedCanonical.isNotEmpty
            ? normalizedCanonical
            : null,
        testMode: testMode,
      ),
    );
  }

  @override
  State<CandidateDetailsSheet> createState() => _CandidateDetailsSheetState();
}

class _CandidateDetailsSheetState extends State<CandidateDetailsSheet> {
  final _db = FirebaseFirestore.instance;
  final _contactAccess = ContactAccessController.instance;
  final Set<String> _birthDateParseFailLogged = <String>{};

  bool _isFetchingContact = false;
  bool _unlockInProgress = false;
  String? _resolvedCanonicalId;
  bool _rebuildQueued = false;
  VoidCallback? _queuedMutation;
  Map<String, dynamic>? _lastCandidateMapForResolution;
  late final int _detailsUiLogSession;
  String? _lastCandidateDetailsLoadingLogSig;
  final Set<String> _contactOfferBlockedLogDedupe = <String>{};

  String get _canonicalId =>
      (_resolvedCanonicalId ?? widget.canonicalCandidateId ?? '').trim();
  bool get _hasCanonicalId => _canonicalId.isNotEmpty;

  void _syncContactResolutionFromCandidate(Map<String, dynamic> candidate) {
    final docCanon =
        CandidateIdentityResolver.resolveCanonicalCandidateIdFromMap(candidate);
    if (docCanon.isNotEmpty) {
      _contactAccess.registerCanonicalMapping(
        canonicalCandidateId: docCanon,
        candidateId: widget.candidateId.trim(),
      );
    }
  }

  /// Resolved backend unlock/contact key (canonical UUID when known).
  String _effectiveResolvedContactKey() {
    final cand = _lastCandidateMapForResolution;
    final docCanon = cand != null
        ? CandidateIdentityResolver.resolveCanonicalCandidateIdFromMap(cand)
        : '';
    final effectiveCanon =
        (_canonicalId.isNotEmpty ? _canonicalId : docCanon).trim();
    return _contactAccess
        .resolveCandidateContactKey(
          candidateId: widget.candidateId.trim(),
          candidateKey: widget.candidateUid.trim(),
          canonicalCandidateId:
              effectiveCanon.isNotEmpty ? effectiveCanon : null,
        )
        .trim();
  }

  bool get _hasResolvedKey => _effectiveResolvedContactKey().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _detailsUiLogSession = identityHashCode(this);

    final rawCanonical = (widget.canonicalCandidateId ?? '').trim();
    _resolvedCanonicalId = CandidateDetailsSheet._isUuid(rawCanonical)
        ? rawCanonical
        : null;

    if (_hasCanonicalId) {
      _contactAccess.registerCanonicalMapping(
        canonicalCandidateId: _canonicalId,
        candidateId: widget.candidateId,
      );
    }

    // Capture exact expanded-details context before any auth/payment continuation.
    NavigationReturnSnapshot.setPendingCandidateDetails(
      candidateId: widget.candidateId,
      candidateUid: widget.candidateUid,
      canonicalCandidateId: _hasCanonicalId ? _canonicalId : null,
    );
    _contactAccess.setPendingOrigin(
      ContactUnlockOriginContext(
        source: ContactUnlockSource.expandedCandidateCard,
        candidateId: widget.candidateId,
        candidateUid: widget.candidateUid,
        canonicalId: _hasCanonicalId ? _canonicalId : null,
        resolvedKey: _hasResolvedKey ? _effectiveResolvedContactKey() : null,
      ),
    );

    _contactAccess.addListener(_onContactAccessChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _primeUnlockedContact();
      if (mounted) _safeRebuild();
    });
  }

  @override
  void dispose() {
    final wid = widget.candidateId.trim();
    final wuid = widget.candidateUid.trim();
    final pendingId = NavigationReturnSnapshot.pendingCandidateId?.trim();
    final pendingUid = NavigationReturnSnapshot.pendingCandidateUid?.trim();
    if (pendingId != null &&
        pendingUid != null &&
        pendingId == wid &&
        pendingUid == wuid) {
      NavigationReturnSnapshot.clearPendingDetails();
    }
    CandidateDetailsUiLogOnce.release(_detailsUiLogSession);
    _contactAccess.removeListener(_onContactAccessChanged);
    super.dispose();
  }

  void _safeRebuild([VoidCallback? mutate]) {
    if (!mounted) return;
    if (mutate != null) {
      final previous = _queuedMutation;
      if (previous == null) {
        _queuedMutation = mutate;
      } else {
        _queuedMutation = () {
          previous();
          mutate();
        };
      }
    }
    if (_rebuildQueued) {
      return;
    }
    _rebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase != SchedulerPhase.idle) {
        _rebuildQueued = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _safeRebuild());
        return;
      }
      _rebuildQueued = false;
      if (!mounted) return;
      final pendingMutation = _queuedMutation;
      _queuedMutation = null;
      setState(() {
        pendingMutation?.call();
      });
    });
  }

  void _setUnlockInProgressSafely(bool value) {
    if (!mounted) return;
    _safeRebuild(() => _unlockInProgress = value);
  }

  void _onContactAccessChanged() {
    if (!mounted) return;
    final scopeReady = _contactAccess.ensureContactBuyerScopeReady(
      source: 'candidate_details_sheet.onContactAccessChanged',
      silent: true,
    );
    if (!scopeReady.isValid) {
      RuntimeFlowLogger.mark(
        'CONTACT_DETAILS_UPDATE_DEFERRED_SCOPE_NOT_READY',
        <String, Object?>{
          'candidateId': widget.candidateId.trim(),
          'resolvedKey': _effectiveResolvedContactKey(),
          'reason': scopeReady.reason,
          'source': 'candidate_details_sheet.onContactAccessChanged',
        },
      );
      _safeRebuild();
      return;
    }

    final rk = _effectiveResolvedContactKey();
    final hasAccess =
        rk.isNotEmpty && _contactAccess.hasAccessToCandidateContact(rk);
    final hasContact =
        rk.isNotEmpty && _contactAccess.contactForCandidate(rk) != null;

    if (hasAccess && !hasContact) {
      unawaited(_triggerContactFetchIfNeeded());
    }

    if (_unlockInProgress && hasAccess && hasContact) {
      _safeRebuild(() => _unlockInProgress = false);
      return;
    }

    _safeRebuild();
  }

  Future<void> _primeUnlockedContact() async {
    final scopeReady = _contactAccess.ensureContactBuyerScopeReady(
      source: 'candidate_details_sheet.primeUnlockedContact',
    );
    if (!scopeReady.isValid) return;
    if (!mounted) return;

    final rk = _effectiveResolvedContactKey();
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final isGuest =
        !isBiz && (user == null || user.isAnonymous || uid.isEmpty);
    final buyerScope = _contactAccess.resolveContactBuyerScope();
    final ownerType = isGuest
        ? 'guest'
        : (isBiz ? 'business' : 'personal');
    final ownerId = isGuest
        ? buyerScope.buyerOwnerId
        : (isBiz ? app_mode.AppMode.activeCompanyId.trim() : uid);
    RuntimeFlowLogger.mark('CONTACT_ACCESS_SUMMARY', <String, Object?>{
      'candidateId': widget.candidateId.trim(),
      'resolvedKey': rk,
      'ownerType': ownerType,
      'ownerId': ownerId,
      'isGuest': isGuest,
      'buyerSig': buyerScope.buyerSig,
      'bootstrapReady': _contactAccess.isBootstrapReadyForCurrentScope,
      'credits': _contactAccess.creditsBalance,
      'hasAccess':
          rk.isNotEmpty && _contactAccess.hasAccessToCandidateContact(rk),
      'contactLoaded':
          rk.isNotEmpty && _contactAccess.contactForCandidate(rk) != null,
      'lastWalletRefreshAt':
          _contactAccess.lastWalletRefreshAt?.toUtc().toIso8601String(),
      'lastAccessRefreshAt':
          _contactAccess.lastAccessRefreshAt?.toUtc().toIso8601String(),
      'source': 'candidate_details_sheet',
      'paywallDebugReason':
          _contactAccess.describeContactPaywallDebugReason(
        resolvedCandidateKey: rk,
      ),
    });

    if (!_hasResolvedKey) return;

    if (_contactAccess.hasAccessToCandidateContact(_effectiveResolvedContactKey())) {
      await _triggerContactFetchIfNeeded();
    }
  }

  Future<void> _triggerContactFetchIfNeeded() async {
    if (!_hasResolvedKey) return;
    if (_isFetchingContact) return;

    final rk = _effectiveResolvedContactKey();
    final hasAccess = _contactAccess.hasAccessToCandidateContact(rk);
    final hasContact = _contactAccess.contactForCandidate(rk) != null;

    if (!hasAccess || hasContact) return;

    _isFetchingContact = true;
    try {
      await _contactAccess.fetchContactForCandidate(rk);
    } finally {
      _isFetchingContact = false;
      _safeRebuild();
    }
  }

  Future<void> _handlePostPayment(String canonicalId) async {
    final id = canonicalId.trim();
    if (!mounted || id.isEmpty) return;
    _setUnlockInProgressSafely(true);
    try {
      await _contactAccess.refreshUnlocked(force: true);
      if (_contactAccess.hasAccessToCandidateContact(id)) {
        try {
          await _contactAccess.fetchContactForCandidate(id);
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        _setUnlockInProgressSafely(false);
        _safeRebuild(() {});
      }
    }
  }

  Future<void> _runDebugContactRestoreVerifier() async {
    if (!mounted || !_hasResolvedKey || !kDebugMode) return;
    _setUnlockInProgressSafely(true);
    try {
      await _contactAccess.debugVerifyRestoreAfterPayment(
        context,
        candidateId: widget.candidateId,
        canonicalCandidateId: _canonicalId,
        candidateUid: widget.candidateUid,
        source: ContactUnlockSource.expandedCandidateCard,
        onExpandedRestore: (candidateId, canonicalId, candidateUid) async {
          final key = (canonicalId ?? '').trim().isNotEmpty
              ? canonicalId!.trim()
              : _effectiveResolvedContactKey();
          if (key.isNotEmpty) {
            await _contactAccess.ensureLoadedContactForCandidate(key);
          }
          if (mounted) {
            _safeRebuild();
          }
        },
      );
    } finally {
      if (mounted) {
        _setUnlockInProgressSafely(false);
      }
    }
  }

  Widget _buildDebugRestoreVerifierButton() {
    if (!kDebugMode || !_hasResolvedKey) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _runDebugContactRestoreVerifier,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bug_report, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Verify Restore',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openOfferPicker(Map<String, dynamic> candidate) async {
    final candidateUid = _s(
      widget.candidateUid,
      fallback: _s(
        candidate['ownerId'],
        fallback: _s(
          candidate['ownerUid'],
          fallback: _s(
            candidate['candidateUid'],
            fallback: _s(candidate['uid'], fallback: _s(candidate['userId'])),
          ),
        ),
      ),
    );

    if (candidateUid.isEmpty) {
      debugPrint(
        'CandidateDetailsSheet: candidateUid missing. candidate keys: ${candidate.keys.toList()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось определить кандидата'),
          backgroundColor: WorkaColors.textDark,
        ),
      );
      return;
    }

    final candidateForOffer = Map<String, dynamic>.from(candidate);
    if (_hasCanonicalId && CandidateDetailsSheet._isUuid(_canonicalId)) {
      candidateForOffer['canonicalCandidateId'] = _canonicalId;
      candidateForOffer['canonicalId'] = _canonicalId;
    }

    final sent = await OfferJobPickerSheet.open(
      context,
      candidateUid: candidateUid,
      candidateCvId: _s(candidate['cvId'], fallback: widget.candidateId),
      candidateData: candidateForOffer,
      testMode: widget.testMode,
    );

    if (sent == true && mounted) {
      Navigator.pop(context);
    }
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  void _logBirthDateFailureOnce(dynamic raw) {
    final key = '${raw.runtimeType}:${raw.toString()}';
    if (_birthDateParseFailLogged.contains(key)) return;
    _birthDateParseFailLogged.add(key);
    RuntimeFlowLogger.mark(
      'CANDIDATE_BIRTHDATE_PARSE_FAILED',
      <String, Object?>{
        'sourceScreen': 'candidate_details_sheet',
        'rawType': raw.runtimeType.toString(),
      },
    );
  }

  DateTime? _dateFromAny(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      final parsed = DateTime.tryParse(t);
      if (parsed == null) {
        _logBirthDateFailureOnce(raw);
      }
      return parsed;
    }

    _logBirthDateFailureOnce(raw);
    return null;
  }

  int? _ageFromCandidate(Map<String, dynamic> candidate) {
    final contacts = (candidate['contacts'] is Map)
        ? Map<String, dynamic>.from(candidate['contacts'])
        : const <String, dynamic>{};

    final birthRaw =
        candidate['birthDate'] ??
        candidate['dateOfBirth'] ??
        contacts['birthDate'] ??
        contacts['dateOfBirth'];

    final date = _dateFromAny(birthRaw);
    if (date == null) return null;

    final now = DateTime.now();
    var age = now.year - date.year;
    final hadBirthday =
        now.month > date.month ||
        (now.month == date.month && now.day >= date.day);

    if (!hadBirthday) age -= 1;
    if (age < 14 || age > 100) return null;
    return age;
  }

  Widget _centerState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: WorkaColors.textGreyDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidateRef = _db
        .collection(FirestorePaths.cvs)
        .doc(widget.candidateId);
    final cvRef = _db.collection(FirestorePaths.cvs).doc(widget.candidateId);

    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: candidateRef.snapshots(),
          builder: (context, candidateSnap) {
            if (!candidateSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }

            if (!candidateSnap.data!.exists) {
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: cvRef.snapshots(),
                builder: (context, cvSnap) {
                  if (!cvSnap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }

                  if (!cvSnap.data!.exists) {
                    return _centerState('Кандидат не найден');
                  }

                  final cvData = cvSnap.data!.data() ?? <String, dynamic>{};
                  final candidate = cv.candidateFromCvDoc(
                    cvData,
                    cvId: widget.candidateId,
                    s: _s,
                  );

                  return _candidateBody(candidate, forceCvData: cvData);
                },
              );
            }

            final candidate = candidateSnap.data!.data() ?? <String, dynamic>{};
            return _candidateBody(candidate);
          },
        ),
      ),
    );
  }

  Widget _candidateBody(
    Map<String, dynamic> candidate, {
    Map<String, dynamic>? forceCvData,
  }) {
    final candidateOwnerId = widget.candidateUid.trim().isNotEmpty
        ? widget.candidateUid.trim()
        : OwnershipResolver.cvOwnerIdFromMap(candidate);

    final ownership = OwnershipResolver.cvViewerOwnership(candidate);
    final ownershipKnown = ownership.known;
    final isOwnCv = ownership.isOwner;
    final cvId = _s(candidate['cvId'], fallback: widget.candidateId);

    _lastCandidateMapForResolution = candidate;
    _syncContactResolutionFromCandidate(candidate);

    final cardCanonForOffer =
        CandidateIdentityResolver.resolveCanonicalCandidateIdFromMap(
      candidate,
    );
    final effectiveCardCanon =
        (_canonicalId.isNotEmpty ? _canonicalId : cardCanonForOffer).trim();

    String? employerOfferScopeId;
    try {
      employerOfferScopeId =
          CanonicalOwnershipResolver.resolveVacancyOwner().ownerId.trim();
    } on StateError {
      employerOfferScopeId = null;
    }

    final offerSentStream = (!ownershipKnown ||
            employerOfferScopeId == null ||
            employerOfferScopeId.isEmpty)
        ? Stream<bool>.value(false)
        : _db
              .collection(FirestorePaths.jobOffers)
              .where('type', isEqualTo: 'offer')
              .where('employerOwnerId', isEqualTo: employerOfferScopeId)
              .where('candidateOwnerId', isEqualTo: candidateOwnerId)
              .where(
                'status',
                whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
              )
              .snapshots()
              .map(
                (s) => mapJobOffersDocsToCardUi(
                  s.docs,
                  employerOwnerScopeId: employerOfferScopeId!,
                  candidateOwnerId: candidateOwnerId,
                  cardCvDocumentId: cvId.trim(),
                  cardCanonicalCandidateId: effectiveCardCanon,
                  cardRawCandidateId: widget.candidateId.trim(),
                ).hasOffer,
              );

    return StreamBuilder<bool>(
      stream: offerSentStream,
      builder: (context, snap) {
        final offerSent = snap.data ?? false;
        final rk = _effectiveResolvedContactKey();
        final hydrationState = rk.isNotEmpty
            ? _contactAccess.stateForCandidateKey(rk)
            : CandidateContactAccessState.initial();
        if (rk.isNotEmpty &&
            hydrationState.hasEntitlement &&
            hydrationState.contact == null &&
            !hydrationState.isLoadingContact &&
            !_unlockInProgress) {
          RuntimeFlowLogger.mark(
            'CONTACT_UI_STATE_ACCESS_WITHOUT_PAYLOAD',
            <String, Object?>{
              'candidateId': widget.candidateId.trim(),
              'canonicalCandidateId': rk,
              'resolvedKey': rk,
              'hasAccess': hydrationState.hasEntitlement,
              'contactLoaded': hydrationState.contact != null,
              'isLoadingContact': hydrationState.isLoadingContact,
              'hasError': hydrationState.error != null,
            },
          );
        }

        final hasUnlockedAccess =
            rk.isNotEmpty && _contactAccess.hasAccessToCandidateContact(rk);

        final contactForCard =
            rk.isNotEmpty ? _contactAccess.contactForCandidate(rk) : null;
        CandidateContact? selfContact;
        if (isOwnCv) {
          final candidateContacts = (candidate['contacts'] is Map)
              ? Map<String, dynamic>.from(candidate['contacts'] as Map)
              : <String, dynamic>{};
          final name = _s(
            candidateContacts['name'],
            fallback: _s(
              candidate['name'],
              fallback: _s(
                '${candidateContacts['firstName'] ?? ''} ${candidateContacts['lastName'] ?? ''}',
              ),
            ),
          );
          final phone = _s(
            candidateContacts['phone'],
            fallback: _s(candidate['phone']),
          );
          final email = _s(
            candidateContacts['email'],
            fallback: _s(candidate['email']),
          );
          final whatsapp = _s(candidateContacts['whatsapp']);
          final telegram = _s(
            candidateContacts['telegram'],
            fallback: _s(candidateContacts['tg']),
          );
          final viber = _s(candidateContacts['viber']);
          final messenger = _s(
            candidateContacts['messenger'],
            fallback: _s(candidateContacts['facebookMessenger']),
          );
          if (name.isNotEmpty ||
              phone.isNotEmpty ||
              email.isNotEmpty ||
              whatsapp.isNotEmpty ||
              telegram.isNotEmpty ||
              viber.isNotEmpty ||
              messenger.isNotEmpty) {
            selfContact = CandidateContact(
              candidateId: rk.isNotEmpty ? rk : widget.candidateId,
              name: name,
              email: email,
              phone: phone,
              whatsapp: whatsapp,
              telegram: telegram,
              viber: viber,
              messenger: messenger,
            );
          }
        }
        final effectiveContactForCard = contactForCard ?? selfContact;
        final effectiveHasUnlockedAccess = isOwnCv || hasUnlockedAccess;
        final contactLoaded = effectiveContactForCard != null;
        final sensitiveContactsReleased =
            isOwnCv ||
            canShowOpenedContact(
              hasAccess: hasUnlockedAccess,
              contactLoaded: contactLoaded,
              contact: effectiveContactForCard,
            );

        if (!isOwnCv && hasUnlockedAccess && !contactLoaded && rk.isNotEmpty) {
          final sig = '${widget.candidateId}|$rk|contact_offer_blocked';
          if (_contactOfferBlockedLogDedupe.add(sig)) {
            RuntimeFlowLogger.mark(
              'CONTACT_OFFER_BLOCKED',
              <String, Object?>{'reason': 'contact_not_loaded'},
            );
          }
        }

        if (_unlockInProgress && effectiveHasUnlockedAccess && contactLoaded) {
          _safeRebuild(() => _unlockInProgress = false);
        }

        final effectiveUnlockInProgress =
            _unlockInProgress && !(effectiveHasUnlockedAccess && contactLoaded);
        final hasContactPayload = effectiveContactForCard != null;
        final canRenderUnlocked =
            effectiveHasUnlockedAccess && contactLoaded && hasContactPayload;
        final paidHydrationFailed =
            effectiveHasUnlockedAccess && !contactLoaded && hydrationState.error != null;
        final uiState = effectiveUnlockInProgress
            ? CandidateDetailsUiState.unlockTransition
            : (canRenderUnlocked
                  ? CandidateDetailsUiState.unlocked
                  : CandidateDetailsUiState.locked);
        final renderedState = canRenderUnlocked
            ? 'unlocked'
            : (paidHydrationFailed ? 'paid_failed' : 'locked');
        RuntimeFlowLogger.mark('CONTACT_UI_STATE_RESOLVED', <String, Object?>{
          'candidateId': widget.candidateId.trim(),
          'resolvedKey': rk,
          'buyerSig': _contactAccess.computeBuyerScopeSig(silent: true),
          'hasAccess': effectiveHasUnlockedAccess,
          'contactLoaded': contactLoaded,
          'hasContact': hasContactPayload,
          'error': hydrationState.error?.toString() ?? '',
          'renderedState': renderedState,
        });
        RuntimeFlowLogger.mark('CANDIDATE_DETAILS_RENDER_UNBLOCKED', <String, Object?>{
          'candidateId': widget.candidateId.trim(),
          'resolvedKey': rk,
          'uiState': 'content_ready',
          'contactRenderedState': renderedState,
        });

        debugPrint(
          '[DETAILS_STATE] '
          'candidateId=${widget.candidateId} canonicalId=$_canonicalId resolvedKey=$rk '
          'uiState=$uiState hasAccess=$effectiveHasUnlockedAccess contactLoaded=$contactLoaded '
          'contactCached=${effectiveContactForCard != null}',
        );

        switch (uiState) {
          case CandidateDetailsUiState.unlockTransition:
            final utSig =
                '${widget.candidateId}|$rk|unlock_transition|$effectiveHasUnlockedAccess|$contactLoaded';
            if (_lastCandidateDetailsLoadingLogSig != utSig) {
              _lastCandidateDetailsLoadingLogSig = utSig;
              RuntimeFlowLogger.mark(
                'CANDIDATE_DETAILS_LOADING_STATE',
                <String, Object?>{
                  'candidateId': widget.candidateId.trim(),
                  'resolvedKey': rk,
                  'reason': 'unlock_transition',
                  'loading': true,
                  'hasAccess': effectiveHasUnlockedAccess,
                  'contactLoaded': contactLoaded,
                },
              );
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );

          case CandidateDetailsUiState.unlocked:
            if (sensitiveContactsReleased) {
              RuntimeFlowLogger.mark(
                'CONTACT_UI_RENDER_UNLOCKED_CONTACTS',
                <String, Object?>{
                  'candidateId': widget.candidateId.trim(),
                  'resolvedKey': rk,
                },
              );
            }
            return Stack(
              children: [
                cv.buildUnlockedContent(
                  db: _db,
                  widgetCandidateId: widget.candidateId,
                  candidate: candidate,
                  cvId: cvId,
                  forceCvData: forceCvData,
                  hasUnlockedAccess: sensitiveContactsReleased,
                  contactForCard: effectiveContactForCard,
                  contactHydrationState: hydrationState,
                  onRetryContactHydration: rk.isNotEmpty
                      ? () {
                          unawaited(
                            _contactAccess.ensureLoadedContactForCandidate(rk),
                          );
                        }
                      : null,
                  resolvedContactKeyForHydrationLog: rk,
                  employerViewCv: (cvData) => cv.employerViewCv(
                    cvData,
                    hasUnlockedAccess: sensitiveContactsReleased,
                  ),
                  buildHeroCard:
                      ({
                        required Map<String, dynamic> candidate,
                      }) => header.buildHeroCard(
                        candidate: candidate,
                        ageFromCandidate: _ageFromCandidate,
                        s: _s,
                        candidateIdForLog: widget.candidateId.trim(),
                        uiLogSessionId: _detailsUiLogSession,
                      ),
                  buildContactsBlock: (contact, cand) =>
                      contacts.buildContactsBlock(
                        context: context,
                        contact: contact,
                        candidate: cand,
                      ),
                  buildContactsLoadingPlaceholder:
                      contacts.buildContactsLoadingPlaceholder,
                  fallbackCandidateCv: (cand) =>
                      cv.fallbackCandidateCv(cand, s: _s),
                ),
                _buildBottomActions(
                  offerSent: offerSent,
                  ownershipKnown: ownershipKnown,
                  isOwnCv: isOwnCv,
                  candidate: candidate,
                  contactConfirmedForOffer: contactLoaded,
                ),
                _buildDebugRestoreVerifierButton(),
              ],
            );

          case CandidateDetailsUiState.locked:
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                RuntimeFlowLogger.mark(
                  'CONTACT_DETAILS_SHEET_POINTER_DOWN',
                  <String, Object?>{
                    'source': 'candidate_details_sheet',
                    'candidateId': widget.candidateId.trim(),
                    'canonicalCandidateId': _canonicalId,
                    'resolvedContactKey': rk,
                    'uiState': 'locked',
                    'dx': event.localPosition.dx,
                    'dy': event.localPosition.dy,
                    'kind': event.kind.name,
                  },
                );
              },
              child: Stack(
              children: [
                cv.buildLockedContent(
                  db: _db,
                  widgetCandidateId: widget.candidateId,
                  candidate: candidate,
                  cvId: cvId,
                  forceCvData: forceCvData,
                  employerViewCv: (cvData) =>
                      cv.employerViewCv(cvData, hasUnlockedAccess: false),
                  buildHeroCard:
                      ({
                        required Map<String, dynamic> candidate,
                      }) => header.buildHeroCard(
                        candidate: candidate,
                        ageFromCandidate: _ageFromCandidate,
                        s: _s,
                        candidateIdForLog: widget.candidateId.trim(),
                        uiLogSessionId: _detailsUiLogSession,
                      ),
                  buildOpenContactsButton:
                      ({
                        required Map<String, dynamic> candidate,
                        required bool contactsOpened,
                      }) {
                        RuntimeFlowLogger.mark(
                          'CONTACT_DETAILS_SHEET_BUILD_CONTACTS_SECTION',
                          <String, Object?>{
                            'source': 'candidate_details_sheet',
                            'candidateId': widget.candidateId.trim(),
                            'canonicalCandidateId': _canonicalId,
                            'resolvedContactKey': rk,
                            'isGuest': () {
                              final u = FirebaseAuth.instance.currentUser;
                              final isBiz = app_mode.AppMode.currentMode ==
                                  app_mode.AccountMode.business;
                              return !isBiz && (u == null || u.isAnonymous);
                            }(),
                            'buyerSig':
                                _contactAccess.computeBuyerScopeSig(),
                            'contactsOpened': contactsOpened,
                            'uiState': 'locked',
                          },
                        );
                        return contacts.buildOpenContactsButton(
                          context: context,
                          candidate: candidate,
                          contactsOpened: contactsOpened,
                          widgetCandidateId: widget.candidateId,
                          canonicalId: _canonicalId,
                          resolvedContactKey: rk,
                          contactAccess: _contactAccess,
                          handlePostPayment: _handlePostPayment,
                          toastBlocked: () {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Не удалось определить кандидата для открытия контактов. Обновите поиск или попробуйте позже.',
                                ),
                              ),
                            );
                          },
                          s: _s,
                        );
                      },
                  fallbackCandidateCv: (cand) =>
                      cv.fallbackCandidateCv(cand, s: _s),
                ),
                _buildDebugRestoreVerifierButton(),
              ],
              ),
            );
        }
      },
    );
  }

  Widget _buildBottomActions({
    required bool offerSent,
    required bool ownershipKnown,
    required bool isOwnCv,
    required Map<String, dynamic> candidate,
    required bool contactConfirmedForOffer,
  }) {
    if (!ownershipKnown) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.blue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Готово',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isOwnCv) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: WorkaColors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text(
                    'Редактировать CV',
                    style: TextStyle(
                      color: WorkaColors.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text(
                    'Готово',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: offerSent
              ? Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: WorkaColors.orange,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Предложение отправлено',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                )
              : Tooltip(
                  message: contactConfirmedForOffer
                      ? ''
                      : 'Сначала загрузите контакты кандидата',
                  child: ElevatedButton(
                    onPressed: contactConfirmedForOffer
                        ? () => _openOfferPicker(candidate)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WorkaColors.orange,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      disabledBackgroundColor:
                          WorkaColors.orange.withValues(alpha: 0.45),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.85),
                    ),
                    child: const Text(
                      'Предложить работу',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
