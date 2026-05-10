import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../profile/user_profile_repo.dart';
import '../screens/role_select_screen.dart';
import '../services/app_mode.dart';
import '../services/auth_guard.dart';
import '../services/auth_continuation_store.dart';
import '../services/firestore_paths.dart';
import '../services/navigation_return_snapshot.dart';
import '../services/runtime_flow_logger.dart';
import '../services/env_config.dart';
import '../services/contact_buyer_scope_readiness.dart';
import '../repositories/applications_repository.dart';
import '../data/models/interaction_models.dart';
import '../screens/home/unified_search_filters.dart';
import '../screens/cv/services/cv_draft_storage.dart';
import '../screens/jobs/services/job_draft_storage.dart';
import '../tabs/contact_tab.dart';
import '../tabs/favorites_tab.dart';
import '../tabs/home_tab.dart';
import '../tabs/profile_tab.dart';
import '../screens/favorites_screen.dart' show FavoritesGoHomeNotification;
import '../widgets/ui/bottom_navigation_bar.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_sheet.dart';

class AuthShell extends StatefulWidget {
  final int initialIndex;
  final bool skipAuthSideEffects;
  final bool showUserAvatar;
  final List<Widget>? tabsOverride;

  const AuthShell({
    super.key,
    this.initialIndex = 0,
    this.skipAuthSideEffects = false,
    this.showUserAvatar = true,
    this.tabsOverride,
  });

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  late int _index = widget.initialIndex.clamp(0, 3);
  bool _showBottomNav = true;
  double _scrollAccumulator = 0;
  static const double _scrollThreshold = 12;
  UserProfileRepo? _profileRepo;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  late final List<Widget> _tabs;
  StreamSubscription<User?>? _authSub;
  Timer? _authNullDebounce;
  String _sessionUid = '';
  bool _roleChecked = false;
  bool _pendingRestoreAttempted = false;
  bool _sessionWasAnonymous = false;
  bool _debugContactRestoreTriggered = false;
  bool _debugContactRestorePending = false;
  late final bool _debugContactRestoreEnabledFromUrl;
  late final String _debugContactRestoreCandidateId;
  late final String _debugContactRestoreCanonicalId;
  late final ContactUnlockSource _debugContactRestoreSource;

  void _ensureGuestSessionIdPersistedIfNeeded() {
    if (AppMode.currentMode == AccountMode.business) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return;
    final repo = PaymentsRepository();
    if (repo.peekGuestSessionId().trim().isEmpty) {
      repo.getOrCreateGuestSessionId();
    }
  }

  bool _setAuthenticatedAppMode({
    required AccountMode mode,
    required String uid,
    required String source,
  }) {
    final safeUid = uid.trim();
    final user = FirebaseAuth.instance.currentUser;
    final hasUser = user != null;
    final isAnonymous = user?.isAnonymous ?? false;
    final firebaseSignedInReady =
        safeUid.isNotEmpty && !AuthGuard.isGuestLikeUid(safeUid) && !isAnonymous;
    RuntimeFlowLogger.mark('AUTH_READY_STATE_RESOLVED', <String, Object?>{
      'uid': safeUid,
      'hasUser': hasUser,
      'isAnonymous': isAnonymous,
      'appMode': mode.name,
      'activeCompanyId': AppMode.activeCompanyId.trim(),
      'firebaseSignedInReady': firebaseSignedInReady,
      'authReadyForContactScope': contactBuyerScopeReady(
        user: user,
        appMode: mode,
        activeCompanyId: AppMode.activeCompanyId.trim(),
        guestSessionIdPeek: PaymentsRepository().peekGuestSessionId(),
      ),
      'reason': source,
      'source': 'auth_shell._setAuthenticatedAppMode',
    });
    if (!firebaseSignedInReady) {
      RuntimeFlowLogger.mark('APP_MODE_SET_BLOCKED', <String, Object?>{
        'requestedMode': mode.name,
        'reason': 'auth_uid_not_ready',
        'uid': safeUid,
        'hasUser': hasUser,
        'isAnonymous': isAnonymous,
      });
      return false;
    }
    AppMode.setMode(mode);
    RuntimeFlowLogger.mark('APP_MODE_SET_CONFIRMED', <String, Object?>{
      'mode': mode.name,
      'uid': safeUid,
      'activeCompanyId': AppMode.activeCompanyId.trim(),
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    final qp = Uri.base.queryParameters;
    _debugContactRestoreEnabledFromUrl =
        kDebugMode && (qp['debugContactRestore'] ?? '').trim() == '1';
    _debugContactRestoreCandidateId = (qp['candidateId'] ?? '').trim();
    _debugContactRestoreCanonicalId = (qp['canonicalId'] ?? '').trim();
    final sourceRaw = (qp['source'] ?? '').trim();
    _debugContactRestoreSource =
        sourceRaw == ContactUnlockSource.compactCard.name
        ? ContactUnlockSource.compactCard
        : ContactUnlockSource.expandedCandidateCard;
    _tabs =
        widget.tabsOverride ??
        const [HomeTab(), FavoritesTab(), ProfileTab(), ContactTab()];
    _sessionUid = (AuthGuard.effectiveUidOrNull() ?? '').trim();
    _sessionWasAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    final restoredIndex = NavigationReturnSnapshot.tabIndex;
    if (restoredIndex != null) {
      _index = restoredIndex.clamp(0, 3);
    }
    NavigationReturnSnapshot.captureTab(_index);
    if (!widget.skipAuthSideEffects) {
      _profileRepo = UserProfileRepo();
      _ensureProfile();
    } else {
      _roleChecked = true;
    }

    // Payment/contact restore runs before buyer-scope bootstrap so guest_session_id
    // + pending origin hydrate unlock lists before list/search widgets stampede.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_pendingRestoreAttempted) return;
      _pendingRestoreAttempted = true;
      await _attemptRestoreContactOrigin();
      if (!mounted) return;
      _ensureGuestSessionIdPersistedIfNeeded();
      if (!mounted) return;
      if (!widget.skipAuthSideEffects) {
        unawaited(
          ContactAccessController.instance.bootstrapForBuyerScopeIfStale(
            source: 'auth_shell.initState',
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authNullDebounce?.cancel();
    super.dispose();
  }

  void _onAuthChanged(User? user) {
    final nextUid = (user == null || user.isAnonymous)
        ? (AuthGuard.effectiveUidOrNull() ?? '').trim()
        : user.uid.trim();
    final firebaseSignedInReady =
        nextUid.isNotEmpty &&
        !AuthGuard.isGuestLikeUid(nextUid) &&
        !(user?.isAnonymous ?? false);
    RuntimeFlowLogger.mark('AUTH_READY_STATE_RESOLVED', <String, Object?>{
      'uid': nextUid,
      'hasUser': user != null,
      'isAnonymous': user?.isAnonymous ?? false,
      'appMode': AppMode.currentMode.name,
      'activeCompanyId': AppMode.activeCompanyId.trim(),
      'firebaseSignedInReady': firebaseSignedInReady,
      'authReadyForContactScope': contactBuyerScopeReady(
        user: user,
        appMode: AppMode.currentMode,
        activeCompanyId: AppMode.activeCompanyId.trim(),
        guestSessionIdPeek: PaymentsRepository().peekGuestSessionId(),
      ),
      'reason': 'firebase_auth_state_changed',
      'source': 'auth_shell._onAuthChanged',
    });
    RuntimeFlowLogger.mark('AUTH_UID_RESOLVE', <String, Object?>{
      'source': 'firebase',
      'uid': nextUid,
    });
    if (nextUid == _sessionUid) return;

    if (nextUid.isEmpty && _sessionUid.isNotEmpty) {
      // UID went null while we had a real session. This can be a transient
      // token-refresh event. Debounce before reacting so we don't pop all
      // routes on a momentary null that resolves within ~1500 ms (Stripe return, app resume).
      _authNullDebounce?.cancel();
      _authNullDebounce = Timer(const Duration(milliseconds: 1500), () {
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) return; // auth was restored — ignore
        // Genuine sign-out confirmed after debounce.
        _applyUidChange('', currentUser: null);
      });
      return;
    }

    _authNullDebounce?.cancel();
    _applyUidChange(nextUid, currentUser: user);

    if (_debugContactRestoreEnabledFromUrl &&
        _debugContactRestorePending &&
        _isRealAuthenticatedUser(user)) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pendingRestoreAttempted = false;
          _attemptRestoreContactOrigin();
        });
      }
    }
  }

  void _applyUidChange(String nextUid, {required User? currentUser}) {
    if (nextUid == _sessionUid) return;

    final prevUid = _sessionUid;
    final isAccountSwitch = _isHardAccountSwitch(
      previousUid: prevUid,
      nextUid: nextUid,
    );
    final cachedGuestUid = (AuthGuard.cachedGuestUid ?? '').trim();
    final previousOwnerUid = prevUid.trim().isNotEmpty
        ? prevUid.trim()
        : (AuthGuard.isGuestLikeUid(cachedGuestUid) ? cachedGuestUid : '');
    final prevWasAnonymous = _sessionWasAnonymous;
    if (isAccountSwitch) {
      RuntimeFlowLogger.mark('ACCOUNT_SWITCH_DETECTED', <String, Object?>{
        'previousUid': prevUid,
        'nextUid': nextUid,
        'prevWasAnonymous': prevWasAnonymous,
        'nextIsAnonymous': currentUser?.isAnonymous ?? false,
      });
    }
    if (kDebugMode) {
      debugPrint(
        'AuthShell uid changed ${prevUid.isEmpty ? "<guest>" : prevUid} -> ${nextUid.isEmpty ? "<guest>" : nextUid}. Resetting session UI state.',
      );
    }

    final switchInProgress = NavigationReturnSnapshot.accountSwitchInProgress;
    _sessionUid = nextUid;
    _sessionWasAnonymous = currentUser?.isAnonymous ?? false;
    _clearSessionMonetizationState(
      reason: switchInProgress ? 'account_switch' : 'auth_uid_change',
      previousUid: prevUid,
      nextUid: nextUid,
      clearPendingIntents: isAccountSwitch,
    );
    if (!widget.skipAuthSideEffects && nextUid.trim().isNotEmpty) {
      unawaited(_ensureProfile());
    }

    final nextUidTrim = nextUid.trim();
    // Safety net: once Firebase auth restoration delivered a real UID, never
    // leave AppMode lingering in `unknown` while Firestore profile hydrates.
    // Default to personal; `_restoreAccountMode` will upgrade to business if
    // the user's profile selects business. This guarantees that contact-scope
    // and downstream auth-ready callers never observe `appMode=unknown` for
    // an authenticated user.
    if (nextUidTrim.isNotEmpty &&
        !AuthGuard.isGuestLikeUid(nextUidTrim) &&
        !(currentUser?.isAnonymous ?? false) &&
        AppMode.currentMode == AccountMode.unknown) {
      _setAuthenticatedAppMode(
        mode: AccountMode.personal,
        uid: nextUidTrim,
        source: 'auth_shell._applyUidChange.default_personal',
      );
    }
    final eligibleGuestContinuation = !switchInProgress &&
        nextUidTrim.isNotEmpty &&
        !AuthGuard.isGuestLikeUid(nextUidTrim) &&
        previousOwnerUid.isNotEmpty &&
        (prevWasAnonymous || AuthGuard.isGuestLikeUid(previousOwnerUid));

    if (eligibleGuestContinuation) {
      RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_START', <String, Object?>{
        'prevUid': previousOwnerUid,
        'nextUid': nextUidTrim,
        'source': 'auth_uid_change',
      });
      unawaited(
        _runPostAuthOwnershipContinuation(
          previousUid: previousOwnerUid,
          nextUid: nextUidTrim,
        ),
      );
    } else if (!switchInProgress &&
        nextUidTrim.isNotEmpty &&
        !AuthGuard.isGuestLikeUid(nextUidTrim) &&
        prevUid.trim().isEmpty) {
      // Signed-out / empty shell session → email/password sign-in: guest-style
      // continuation never ran (previousOwnerUid empty). Still resume contact
      // purchase intent if it was captured before AuthEntryScreen.
      unawaited(_maybeResumeContactPurchaseAfterColdSignIn(nextUidTrim));
    }

    if (switchInProgress) {
      NavigationReturnSnapshot.setHomeMode(SearchMode.vacancies);
      if (nextUid.isNotEmpty) {
        NavigationReturnSnapshot.finishAccountSwitch();
      }
      if (mounted) setState(() {});
      return;
    }

    NavigationReturnSnapshot.setHomeMode(SearchMode.vacancies);

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _pendingRestoreAttempted = false;
        await _attemptRestoreContactOrigin();
        if (!mounted) return;
        _ensureGuestSessionIdPersistedIfNeeded();
        if (!mounted) return;
        if (!widget.skipAuthSideEffects) {
          unawaited(
            ContactAccessController.instance.bootstrapForBuyerScopeIfStale(
              source: 'auth_shell._applyUidChange',
            ),
          );
        }
      });
      setState(() {});
    }
  }

  Future<void> _maybeResumeContactPurchaseAfterColdSignIn(String nextUid) async {
    if (!mounted) return;
    await _consumeAndResumeContactPurchaseIntent(nextUid: nextUid);
  }

  Future<void> _runPostAuthOwnershipContinuation({
    required String previousUid,
    required String nextUid,
  }) async {
    RuntimeFlowLogger.mark('AUTH_UID_RESOLVE', <String, Object?>{
      'source': 'firebase',
      'uid': nextUid,
    });
    RuntimeFlowLogger.mark('AUTH_CONTINUATION_PROCESS_START', <String, Object?>{
      'uid': nextUid,
      'prevUid': previousUid,
      'nextUid': nextUid,
    });
    RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_START', <String, Object?>{
      'prevUid': previousUid,
      'nextUid': nextUid,
    });
    try {
      final cvReownResult = await _reownGuestCvViaApi(
        previousUid: previousUid,
        nextUid: nextUid,
      );
      final cvStoreReowned = await _consumeAndReownCvDraftFromStore(
        previousUid: previousUid,
        nextUid: nextUid,
      );
      final db = FirebaseFirestore.instance;
      final cvDraftReowned = await _reownPendingCvDraft(
        previousUid: previousUid,
        nextUid: nextUid,
      );
      RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_DONE', <String, Object?>{
        'prevUid': previousUid,
        'nextUid': nextUid,
        'apiReowned': cvReownResult,
        'storeDraftReowned': cvStoreReowned,
        'localDraftReowned': cvDraftReowned,
      });

      final jobStoreReowned = await _consumeAndReownVacancyDraftFromStore(
        previousUid: previousUid,
        nextUid: nextUid,
      );
      var jobUpdated = 0;
      for (final collection in <String>[
        FirestorePaths.vacancies,
        FirestorePaths.vacanciesTest,
      ]) {
        final snap = await db
            .collection(collection)
            .where('ownerId', isEqualTo: previousUid)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final ownerType = (data['ownerType'] ?? '').toString().trim();
          if (ownerType == 'business') continue;
          await doc.reference.update(<String, dynamic>{
            'ownerType': 'personal',
            'ownerId': nextUid,
            'ownerUid': nextUid,
            'createdByUserId': nextUid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          jobUpdated += 1;
        }
      }
      debugPrint(
        '[JOB_AUTH_CONTINUATION_START] prevUid=$previousUid nextUid=$nextUid updated=$jobUpdated',
      );
      final jobDraftReowned = await _reownPendingJobDraft(
        previousUid: previousUid,
        nextUid: nextUid,
      );
      debugPrint(
        '[JOB_AUTH_CONTINUATION_REOWN] prevUid=$previousUid nextUid=$nextUid storeDraftReowned=$jobStoreReowned localDraftReowned=$jobDraftReowned updated=$jobUpdated',
      );
      debugPrint(
        '[JOB_AUTH_CONTINUATION_DONE] prevUid=$previousUid nextUid=$nextUid updated=$jobUpdated',
      );

      final resumedApplyFromStore = await _consumeAndResumeApplyIntentFromStore(
        db: db,
        nextUid: nextUid,
      );
      final resumedApply =
          await ApplicationsRepository.resumePendingApplyIntentAfterAuth(
            db: db,
            authenticatedUid: nextUid,
          );
      if (resumedApply || resumedApplyFromStore) {
        RuntimeFlowLogger.mark('APPLY_SEND_RESULT', <String, Object?>{
          'status': 'success',
          'source': 'auth_continuation',
          'uid': nextUid,
        });
      }
      debugPrint(
        '[APPLY_AUTH_CONTINUATION_DONE] uid=$nextUid resumedFromStore=$resumedApplyFromStore resumedFromLegacy=$resumedApply',
      );

      final resumedContactPurchase = await _consumeAndResumeContactPurchaseIntent(
        nextUid: nextUid,
      );
      final paymentContextRestored = resumedContactPurchase
          ? false
          : await _consumeAndRestorePaymentReturnContext();
      RuntimeFlowLogger.mark('AUTH_CONTINUATION_PROCESS_DONE', <String, Object?>{
        'prevUid': previousUid,
        'nextUid': nextUid,
        'cvApiReowned': cvReownResult,
        'jobUpdated': jobUpdated,
        'cvDraftReowned': cvDraftReowned,
        'jobDraftReowned': jobDraftReowned,
        'applyResumed': resumedApply || resumedApplyFromStore,
        'contactPurchaseResumed': resumedContactPurchase,
        'paymentContextRestored': paymentContextRestored,
      });
      debugPrint(
        '[AUTH_CONTINUATION_PROCESS_DONE] prevUid=$previousUid nextUid=$nextUid '
        'cvApiReowned=$cvReownResult jobUpdated=$jobUpdated cvDraftReowned=$cvDraftReowned jobDraftReowned=$jobDraftReowned '
        'applyResumed=${resumedApply || resumedApplyFromStore} '
        'contactPurchaseResumed=$resumedContactPurchase '
        'paymentContextRestored=$paymentContextRestored',
      );
    } catch (e) {
      RuntimeFlowLogger.mark('AUTH_CONTINUATION_PROCESS_DONE', <String, Object?>{
        'prevUid': previousUid,
        'nextUid': nextUid,
        'error': e.toString(),
      });
      RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_DONE', <String, Object?>{
        'prevUid': previousUid,
        'nextUid': nextUid,
        'error': e.toString(),
      });
      debugPrint(
        '[AUTH_CONTINUATION_PROCESS_DONE] prevUid=$previousUid nextUid=$nextUid error=$e',
      );
    }
  }

  Future<bool> _reownGuestCvViaApi({
    required String previousUid,
    required String nextUid,
  }) async {
    final guestId = previousUid.trim();
    final userId = nextUid.trim();
    if (guestId.isEmpty || userId.isEmpty) return false;
    if (!AuthGuard.isGuestLikeUid(guestId)) return false;
    RuntimeFlowLogger.mark('CV_REOWN_START', <String, Object?>{
      'guestId': guestId,
      'uid': userId,
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token == null || token.isEmpty) {
        RuntimeFlowLogger.mark('CV_REOWN_FAILED', <String, Object?>{
          'guestId': guestId,
          'uid': userId,
          'reason': 'auth_token_missing',
        });
        return false;
      }
      final base = EnvConfig.workaApiBaseUrl(allowDevFallback: !kReleaseMode);
      if (base == null || base.trim().isEmpty) {
        RuntimeFlowLogger.mark('CV_REOWN_FAILED', <String, Object?>{
          'guestId': guestId,
          'uid': userId,
          'reason': 'api_base_missing',
        });
        return false;
      }
      final uri = Uri.parse('$base/candidates/cv/reown-guest');
      final resp = await http.post(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'x-user-id': userId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'guestId': guestId,
          'userId': userId,
          'ownerType': 'personal',
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        RuntimeFlowLogger.mark('CV_REOWN_FAILED', <String, Object?>{
          'guestId': guestId,
          'uid': userId,
          'code': resp.statusCode,
          'body': resp.body,
        });
        return false;
      }
      RuntimeFlowLogger.mark('CV_REOWN_SUCCESS', <String, Object?>{
        'guestId': guestId,
        'uid': userId,
        'body': resp.body,
      });
      RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_REOWN', <String, Object?>{
        'previousUid': guestId,
        'nextUid': userId,
        'source': 'api_reown_guest_cv',
      });
      final myCvsVisible = await FirebaseFirestore.instance
          .collection(FirestorePaths.cvs)
          .where('ownerId', isEqualTo: userId)
          .limit(1)
          .get();
      RuntimeFlowLogger.mark('CV_MY_CVS_VISIBLE_AFTER_REOWN', <String, Object?>{
        'uid': userId,
        'visible': myCvsVisible.docs.isNotEmpty,
      });
      return true;
    } catch (e) {
      RuntimeFlowLogger.mark('CV_REOWN_FAILED', <String, Object?>{
        'guestId': guestId,
        'uid': userId,
        'reason': e.toString(),
      });
      return false;
    }
  }

  Future<bool> _consumeAndReownCvDraftFromStore({
    required String previousUid,
    required String nextUid,
  }) async {
    final pending = await AuthContinuationStore.instance
        .consumePendingCvDraft();
    if (pending == null) return false;
    final next = nextUid.trim();
    if (next.isEmpty) return false;
    pending['ownerId'] = next;
    pending['ownerKey'] = next;
    pending['ownerUid'] = next;
    pending['owner_uid'] = next;
    pending['ownerType'] = 'personal';
    pending['owner_type'] = 'personal';
    pending['isRegistered'] = true;
    pending.remove('label');
    pending.remove('candidateLabel');
    pending['candidateId'] = next;
    pending['candidate_id'] = next;
    await CvDraftStorage.save(pending);
    RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_REOWN', <String, Object?>{
      'previousUid': previousUid,
      'nextUid': next,
      'source': 'auth_continuation_store',
    });
    return true;
  }

  Future<bool> _consumeAndReownVacancyDraftFromStore({
    required String previousUid,
    required String nextUid,
  }) async {
    final pending = await AuthContinuationStore.instance
        .consumePendingVacancyDraft();
    if (pending == null) return false;
    final next = nextUid.trim();
    if (next.isEmpty) return false;
    final ownerIntent = (pending['ownerIntent'] ?? '').toString().trim();
    RuntimeFlowLogger.mark('GUEST_VACANCY_AUTH_RESUME', <String, Object?>{
      'previousUid': previousUid,
      'nextUid': next,
      'ownerIntent': ownerIntent,
      'guestId': (pending['guestId'] ?? '').toString().trim(),
    });
    final useBusinessIntent = ownerIntent == 'business';
    var businessOwnerId = AppMode.activeCompanyId.trim();
    if (useBusinessIntent) {
      RuntimeFlowLogger.mark('GUEST_VACANCY_PROFILE_CREATE_START', <String, Object?>{
        'uid': next,
        'ownerIntent': 'business',
      });
      businessOwnerId = await _ensureBusinessCompanyForVacancyIntent(
        uid: next,
        pending: pending,
      );
      RuntimeFlowLogger.mark('GUEST_VACANCY_PROFILE_CREATE_DONE', <String, Object?>{
        'uid': next,
        'ownerIntent': 'business',
        'companyId': businessOwnerId,
      });
      if (businessOwnerId.isEmpty) {
        RuntimeFlowLogger.mark('GUEST_VACANCY_PUBLISH_FAILED', <String, Object?>{
          'uid': next,
          'ownerIntent': 'business',
          'reason': 'business_company_missing',
        });
        await AuthContinuationStore.instance.savePendingVacancyDraft(pending);
        return false;
      }
    } else {
      RuntimeFlowLogger.mark('GUEST_VACANCY_PROFILE_CREATE_START', <String, Object?>{
        'uid': next,
        'ownerIntent': 'personal',
      });
      await _ensurePersonalProfileForVacancyIntent(uid: next);
      RuntimeFlowLogger.mark('GUEST_VACANCY_PROFILE_CREATE_DONE', <String, Object?>{
        'uid': next,
        'ownerIntent': 'personal',
      });
    }
    final ownerType = useBusinessIntent ? 'business' : 'personal';
    final ownerId = useBusinessIntent ? businessOwnerId : next;
    pending['ownerType'] = ownerType;
    pending['ownerId'] = ownerId;
    pending['ownerUid'] = next;
    pending['createdByUserId'] = next;
    pending['companyId'] = useBusinessIntent ? ownerId : null;
    if (useBusinessIntent && ownerId.isEmpty) {
      RuntimeFlowLogger.mark('GUEST_VACANCY_PUBLISH_FAILED', <String, Object?>{
        'uid': next,
        'reason': 'business_scope_missing_company_id',
      });
      RuntimeFlowLogger.mark('BUSINESS_SCOPE_RESOLVE', <String, Object?>{
        'status': 'missing',
        'action': 'open_create_business_profile',
        'reason': 'guest_vacancy_business_intent_missing_company_id',
      });
    }
    await JobDraftStorage.save(pending);
    debugPrint(
      '[JOB_AUTH_CONTINUATION_REOWN] previousUid=$previousUid nextUid=$next source=auth_continuation_store ownerType=$ownerType ownerId=$ownerId',
    );
    return true;
  }

  Future<void> _ensurePersonalProfileForVacancyIntent({
    required String uid,
  }) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set(<String, dynamic>{
      'enabledProfiles': FieldValue.arrayUnion(const <String>['personal']),
      'selectedProfile': 'personal',
      'activeProfile': 'personal',
      'role': 'personal',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await AppMode.setActiveCompanyId(null);
    _setAuthenticatedAppMode(
      mode: AccountMode.personal,
      uid: uid,
      source: 'auth_shell._ensurePersonalProfileForVacancyIntent',
    );
  }

  Future<String> _ensureBusinessCompanyForVacancyIntent({
    required String uid,
    required Map<String, dynamic> pending,
  }) async {
    var companyId = AppMode.activeCompanyId.trim();
    final companyDraft = pending['companyDraft'] is Map
        ? Map<String, dynamic>.from(pending['companyDraft'] as Map)
        : const <String, dynamic>{};
    final companyName = (companyDraft['companyName'] ?? '').toString().trim();
    if (companyId.isEmpty) {
      companyId = await _createCompanyFromIntent(
        uid: uid,
        companyName: companyName,
      );
    }
    if (companyId.isEmpty) return '';

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set(<String, dynamic>{
      'enabledProfiles': FieldValue.arrayUnion(const <String>['business']),
      'selectedProfile': 'business',
      'activeProfile': 'business',
      'role': 'business',
      'activeCompanyId': companyId,
      'companyId': companyId,
      'company_id': companyId,
      'business': <String, dynamic>{
        'id': companyId,
        'companyId': companyId,
        'company_id': companyId,
        'companyName': companyName,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await AppMode.setActiveCompanyId(companyId);
    _setAuthenticatedAppMode(
      mode: AccountMode.business,
      uid: uid,
      source: 'auth_shell._ensureBusinessCompanyForVacancyIntent',
    );
    return companyId;
  }

  Future<String> _createCompanyFromIntent({
    required String uid,
    required String companyName,
  }) async {
    final base = EnvConfig.workaApiBaseUrl(allowDevFallback: !kReleaseMode);
    if (base == null || base.trim().isEmpty) return '';
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) return '';
    final uri = Uri.parse('$base/companies');
    final body = jsonEncode(<String, dynamic>{
      'name': companyName.isEmpty ? 'Компания $uid' : companyName,
      'created_by_user_id': uid,
    });
    try {
      final resp = await http.post(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'x-user-id': uid,
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return '';
      }
      final decoded = jsonDecode(resp.body);
      return (decoded is Map
              ? (decoded['company'] is Map
                    ? (decoded['company']['id'] ?? '')
                    : '')
              : '')
          .toString()
          .trim();
    } catch (e) {
      return '';
    }
  }

  Future<bool> _consumeAndResumeApplyIntentFromStore({
    required FirebaseFirestore db,
    required String nextUid,
  }) async {
    final pending = await AuthContinuationStore.instance
        .consumePendingApplyIntent();
    if (pending == null) return false;
    final uid = nextUid.trim();
    if (uid.isEmpty) return false;
    final jobCode = (pending['jobCode'] ?? '').toString().trim();
    final cvId = (pending['cvId'] ?? '').toString().trim();
    final vacancyOwnerId = (pending['vacancyOwnerId'] ?? '').toString().trim();
    final vacancyOwnerType = (pending['vacancyOwnerType'] ?? 'personal')
        .toString()
        .trim();
    if (jobCode.isEmpty || cvId.isEmpty) return false;
    RuntimeFlowLogger.mark('APPLY_AUTH_CONTINUATION_START', <String, Object?>{
      'stage': 'store_resume',
      'uid': uid,
      'vacancyId': jobCode,
      'cvId': cvId,
    });
    final repo = ApplicationsRepository(db);
    await repo.create(
      id:
          (pending['requestId'] ??
                  'apply_${DateTime.now().microsecondsSinceEpoch}')
              .toString()
              .trim(),
      payload: ApplicationCreate(
        vacancyId: jobCode,
        vacancyOwnerId: vacancyOwnerId,
        vacancyOwnerType: vacancyOwnerType.isEmpty
            ? 'personal'
            : vacancyOwnerType,
        candidateId: uid,
        cvId: cvId,
        applicantProfileType: 'personal',
      ),
    );
    return true;
  }

  Future<bool> _consumeAndRestorePaymentReturnContext() async {
    final pending = await AuthContinuationStore.instance
        .consumePendingPaymentReturnContext();
    if (pending == null) return false;
    final rawCvId = stableFirestoreCvIdFromPaymentResumeMap(pending);
    final canonicalId =
        (pending['canonicalId'] ?? pending['canonicalCandidateId'] ?? '')
            .toString()
            .trim();
    final candidateUid = (pending['candidateUid'] ?? '').toString().trim();
    final jobId = (pending['jobId'] ?? '').toString().trim();
    final source = (pending['source'] ?? '').toString().trim();
    final uiMode =
        (pending['uiMode'] ?? pending['mode'] ?? '').toString().trim();
    RuntimeFlowLogger.mark('PAYMENT_RETURN_CONTEXT_RESTORE', <String, Object?>{
      'source': source,
      'mode': uiMode,
      'candidateId': rawCvId,
      'canonicalId': canonicalId,
      'cvId': rawCvId,
      'jobId': jobId,
    });
    debugPrint(
      '[PAYMENT_RETURN_CONTEXT_RESTORE] source=$source mode=$uiMode candidateId=$rawCvId cvId=$rawCvId jobId=$jobId',
    );
    if (rawCvId.isNotEmpty && candidateUid.isNotEmpty) {
      NavigationReturnSnapshot.setPendingCandidateDetails(
        candidateId: rawCvId,
        candidateUid: candidateUid,
        canonicalCandidateId: canonicalId.isNotEmpty ? canonicalId : null,
      );
      ContactAccessController.instance.setPendingOrigin(
        ContactUnlockOriginContext(
          source: uiMode == ContactUnlockSource.compactCard.name
              ? ContactUnlockSource.compactCard
              : ContactUnlockSource.expandedCandidateCard,
          candidateId: rawCvId,
          candidateUid: candidateUid,
          canonicalId: canonicalId.isNotEmpty ? canonicalId : null,
          resolvedKey: canonicalId.isNotEmpty ? canonicalId : null,
        ),
      );
      return true;
    }
    if (jobId.isNotEmpty) {
      NavigationReturnSnapshot.setPendingVacancyDetails(jobId);
      return true;
    }
    return false;
  }

  Future<bool> _consumeAndResumeContactPurchaseIntent({
    required String nextUid,
  }) async {
    final pending = await AuthContinuationStore.instance
        .readPendingContactPurchaseIntent();
    if (pending == null) return false;
    if (!mounted) return false;

    final uid = nextUid.trim();
    if (uid.isEmpty || AuthGuard.isGuestLikeUid(uid)) {
      RuntimeFlowLogger.mark(
        'CONTACT_PURCHASE_CONTINUATION_BLOCKED',
        <String, Object?>{
          'reason': 'auth_uid_invalid',
          'uid': uid,
        },
      );
      RuntimeFlowLogger.mark(
        'AUTH_CONTINUATION_PRESERVED_ON_ERROR',
        <String, Object?>{
          'reason': 'auth_uid_invalid',
          'uid': uid,
        },
      );
      return false;
    }

    final sourceRaw = (pending['source'] ?? '').toString().trim();
    final source = sourceRaw == ContactUnlockSource.compactCard.name
        ? ContactUnlockSource.compactCard
        : ContactUnlockSource.expandedCandidateCard;
    final modeRaw = (pending['mode'] ?? '').toString().trim();
    final mode = modeRaw == PaywallMode.creditsOnly.name
        ? PaywallMode.creditsOnly
        : PaywallMode.directUnlock;
    final candidateId = (pending['candidateId'] ?? '').toString().trim();
    final canonicalId = (pending['canonicalId'] ?? pending['canonicalCandidateId'] ?? '')
        .toString()
        .trim();
    final candidateUid = (pending['candidateUid'] ?? '').toString().trim();
    final sourceScreen = (pending['sourceScreen'] ?? '').toString().trim();
    final selectedProductId = (pending['selectedProductId'] ?? '')
        .toString()
        .trim();
    final checkoutSessionId = (pending['checkoutSessionId'] ?? '')
        .toString()
        .trim();

    final hasDirectUnlockTarget = canonicalId.isNotEmpty;
    if (mode == PaywallMode.directUnlock && !hasDirectUnlockTarget) {
      RuntimeFlowLogger.mark(
        'CONTACT_PURCHASE_CONTINUATION_BLOCKED',
        <String, Object?>{
          'reason': 'missing_direct_unlock_target',
          'mode': mode.name,
          'source': source.name,
          'candidateId': candidateId,
          'canonicalId': canonicalId,
        },
      );
      RuntimeFlowLogger.mark(
        'AUTH_CONTINUATION_PRESERVED_ON_ERROR',
        <String, Object?>{
          'reason': 'missing_direct_unlock_target',
          'mode': mode.name,
          'source': source.name,
          'candidateId': candidateId,
          'canonicalId': canonicalId,
        },
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось продолжить покупку: отсутствует контекст кандидата.',
            ),
          ),
        );
      }
      return false;
    }

    RuntimeFlowLogger.mark(
      'CONTACT_PURCHASE_CONTINUATION_RESTORE',
      <String, Object?>{
        'mode': mode.name,
        'source': source.name,
        'candidateId': candidateId,
        'canonicalId': canonicalId,
        'candidateUid': candidateUid.isNotEmpty ? candidateUid : uid,
        'sourceScreen': sourceScreen,
        'selectedProductId': selectedProductId,
        'checkoutSessionId': checkoutSessionId,
      },
    );

    final resumeResult = await ContactUnlockPaywallSheet.open(
      context,
      candidateId: candidateId.isNotEmpty ? candidateId : null,
      canonicalCandidateId: canonicalId.isNotEmpty ? canonicalId : null,
      candidateUid: candidateUid.isNotEmpty ? candidateUid : uid,
      entryPoint: sourceScreen.isNotEmpty ? sourceScreen : 'auth_continuation',
      mode: mode,
      originContext: ContactUnlockOriginContext(
        source: source,
        candidateId: candidateId.isNotEmpty ? candidateId : canonicalId,
        candidateUid: candidateUid.isNotEmpty ? candidateUid : uid,
        canonicalId: canonicalId.isNotEmpty ? canonicalId : null,
        resolvedKey: canonicalId.isNotEmpty ? canonicalId : null,
      ),
      initialProductId: selectedProductId,
      autoStartPurchase: true,
    );
    final resumed =
        resumeResult.outcome == ContactUnlockPaywallOutcome.checkoutStarted ||
        resumeResult.outcome == ContactUnlockPaywallOutcome.directUnlockSucceeded ||
        resumeResult.outcome == ContactUnlockPaywallOutcome.alreadyUnlocked;

    if (resumed) {
      await AuthContinuationStore.instance.clearPendingContactPurchaseIntent();
      RuntimeFlowLogger.mark(
        'CONTACT_PURCHASE_CONTINUATION_DONE',
        <String, Object?>{
          'resumed': resumed,
          'resumeOutcome': resumeResult.outcome.name,
          'mode': mode.name,
          'source': source.name,
        },
      );
      return true;
    }
    final stillPending = await AuthContinuationStore.instance
        .readPendingContactPurchaseIntent();
    if (stillPending != null) {
      RuntimeFlowLogger.mark(
        'AUTH_CONTINUATION_PRESERVED_ON_ERROR',
        <String, Object?>{
          'reason': 'contact_resume_failed_before_handoff',
          'mode': mode.name,
          'source': source.name,
          'candidateId': candidateId,
          'canonicalId': canonicalId,
          'selectedProductId': selectedProductId,
        },
      );
    }
    RuntimeFlowLogger.mark(
      'CONTACT_PURCHASE_CONTINUATION_DONE',
      <String, Object?>{
        'resumed': resumed,
        'resumeOutcome': resumeResult.outcome.name,
        'mode': mode.name,
        'source': source.name,
      },
    );
    return false;
  }

  Future<bool> _reownPendingCvDraft({
    required String previousUid,
    required String nextUid,
  }) async {
    final draft = await CvDraftStorage.load();
    if (draft == null) return false;
    final prev = previousUid.trim();
    final next = nextUid.trim();
    if (next.isEmpty) return false;
    final ownerId = (draft['ownerId'] ?? '').toString().trim();
    final ownerKey = (draft['ownerKey'] ?? '').toString().trim();
    final candidateId = (draft['candidateId'] ?? '').toString().trim();
    final candidateLegacy = (draft['candidate_id'] ?? '').toString().trim();
    final shouldReown =
        ownerId.isEmpty ||
        ownerKey.isEmpty ||
        candidateId.isEmpty ||
        candidateLegacy.isEmpty ||
        ownerId == prev ||
        ownerKey == prev ||
        candidateId == prev ||
        candidateLegacy == prev ||
        AuthGuard.isGuestLikeUid(ownerId) ||
        AuthGuard.isGuestLikeUid(ownerKey) ||
        AuthGuard.isGuestLikeUid(candidateId) ||
        AuthGuard.isGuestLikeUid(candidateLegacy);
    if (!shouldReown) return false;
    draft['ownerId'] = next;
    draft['ownerKey'] = next;
    draft['ownerUid'] = next;
    draft['owner_uid'] = next;
    draft['ownerType'] = 'personal';
    draft['owner_type'] = 'personal';
    draft['isRegistered'] = true;
    draft.remove('label');
    draft.remove('candidateLabel');
    draft['candidateId'] = next;
    draft['candidate_id'] = next;
    await CvDraftStorage.save(draft);
    RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_REOWN', <String, Object?>{
      'previousUid': previousUid,
      'nextUid': next,
      'localDraft': true,
    });
    return true;
  }

  Future<bool> _reownPendingJobDraft({
    required String previousUid,
    required String nextUid,
  }) async {
    final draft = await JobDraftStorage.load();
    if (draft == null) return false;
    final next = nextUid.trim();
    if (next.isEmpty) return false;
    final ownerIntent = (draft['ownerIntent'] ?? draft['ownerType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final useBusinessIntent = ownerIntent == 'business';
    final businessOwnerId = AppMode.activeCompanyId.trim();
    final ownerType = useBusinessIntent ? 'business' : 'personal';
    final ownerId = useBusinessIntent ? businessOwnerId : next;
    final existingOwnerId = (draft['ownerId'] ?? '').toString().trim();
    final existingOwnerType = (draft['ownerType'] ?? '').toString().trim();
    final shouldReown =
        existingOwnerId.isEmpty ||
        existingOwnerId == previousUid.trim() ||
        AuthGuard.isGuestLikeUid(existingOwnerId) ||
        existingOwnerType != ownerType;
    if (!shouldReown) return false;
    draft['ownerType'] = ownerType;
    draft['ownerId'] = ownerId;
    draft['ownerUid'] = next;
    draft['createdByUserId'] = next;
    draft['companyId'] = useBusinessIntent ? ownerId : null;
    if (useBusinessIntent && ownerId.isEmpty) {
      RuntimeFlowLogger.mark('BUSINESS_SCOPE_RESOLVE', <String, Object?>{
        'status': 'missing',
        'action': 'open_create_business_profile',
        'reason': 'guest_job_draft_business_intent_missing_company_id',
      });
    }
    await JobDraftStorage.save(draft);
    debugPrint(
      '[JOB_AUTH_CONTINUATION_DONE] prevUid=$previousUid nextUid=$next localDraft=true ownerType=$ownerType ownerId=$ownerId ownerIntent=$ownerIntent',
    );
    return true;
  }

  void _clearSessionMonetizationState({
    required String reason,
    required String previousUid,
    required String nextUid,
    required bool clearPendingIntents,
  }) {
    RuntimeFlowLogger.mark('ACCOUNT_SCOPE_CLEAR_START', <String, Object?>{
      'reason': reason,
      'previousUid': previousUid,
      'nextUid': nextUid,
      'clearPendingIntents': clearPendingIntents,
      'activeCompanyIdBefore': AppMode.activeCompanyId.trim(),
    });
    NavigationReturnSnapshot.clearPendingDetails();
    unawaited(AppMode.setActiveCompanyId(null));
    AppMode.setMode(AccountMode.unknown);
    final access = ContactAccessController.instance;
    access.clearPendingOrigin(reason: reason);
    access.lastAttemptedCandidateId = null;
    if (previousUid.isNotEmpty) {
      access.clearPendingUnlockIntentForUid(previousUid);
    }
    if (nextUid.isNotEmpty && nextUid != previousUid) {
      access.clearPendingUnlockIntentForUid(nextUid);
    }
    if (clearPendingIntents) {
      unawaited(AuthContinuationStore.instance.clearAllPendingIntents());
    }
    RuntimeFlowLogger.mark('ACCOUNT_SCOPE_CLEAR_OK', <String, Object?>{
      'reason': reason,
      'previousUid': previousUid,
      'nextUid': nextUid,
      'clearPendingIntents': clearPendingIntents,
      'activeCompanyIdAfter': AppMode.activeCompanyId.trim(),
      'modeAfter': AppMode.currentMode.name,
    });
  }

  /// Blocks sheet reopen when Stripe checkout finished but persisted context
  /// lost the Firestore CV doc id (cannot open [CandidateDetailsSheet] with UUID).
  bool _paymentContactResumeMissingFirestoreCv(Map<String, dynamic>? pendingPay) {
    if (pendingPay == null) return false;
    final modeLower =
        (pendingPay['mode'] ?? '').toString().toLowerCase().trim();
    if (modeLower != 'contact_unlock' && modeLower != 'direct_unlock') {
      return false;
    }
    final sid =
        (pendingPay['checkoutSessionId'] ?? pendingPay['sessionId'] ?? '')
            .toString()
            .trim();
    final canon = (pendingPay['canonicalId'] ??
            pendingPay['canonicalCandidateId'] ??
            '')
        .toString()
        .trim();
    if (sid.isEmpty || canon.isEmpty) return false;
    final raw = stableFirestoreCvIdFromPaymentResumeMap(pendingPay);
    if (raw.isNotEmpty) return false;
    RuntimeFlowLogger.mark('PAYMENT_RETURN_CONTEXT_MISSING', <String, Object?>{
      'missing': 'rawCandidateId,cvId,candidateId',
      'canonicalId': canon,
      'checkoutSessionId': sid,
      'phase': 'auth_shell_restore_blocked',
      'source': 'auth_shell._attemptRestoreContactOrigin',
    });
    return true;
  }

  Future<void> _attemptRestoreContactOrigin() async {
    if (await _tryRunDebugContactRestoreFromUrl()) {
      return;
    }

    debugPrint('[CONTACT_RESTORE_FROM_STORAGE] start');

    Map<String, dynamic>? pendingPay;
    try {
      pendingPay =
          await AuthContinuationStore.instance.readPendingPaymentReturnContext();
    } catch (_) {
      pendingPay = null;
    }
    final pendingGuestSid = (pendingPay?['guestSessionId'] ??
            pendingPay?['guest_session_id'] ??
            '')
        .toString()
        .trim();
    if (pendingGuestSid.isNotEmpty) {
      PaymentsRepository().restoreGuestSessionId(
        pendingGuestSid,
        restoreSource: 'auth_shell_pending_payment_context',
      );
    }

    if (_paymentContactResumeMissingFirestoreCv(pendingPay)) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = (currentUser?.uid ?? '').trim();
    final isAnonymous = currentUser?.isAnonymous ?? false;

    final guestPeek = PaymentsRepository().peekGuestSessionId().trim();
    final origin = ContactAccessController.instance.pendingOrigin;
    final modeLowerResume =
        (pendingPay?['mode'] ?? '').toString().toLowerCase().trim();
    final modeUnlockContact =
        modeLowerResume == 'contact_unlock' ||
        modeLowerResume == 'direct_unlock';
    final pendingCanon =
        (pendingPay?['canonicalId'] ?? '').toString().trim().isNotEmpty;

    final guestBuyerReady =
        guestPeek.isNotEmpty || pendingGuestSid.isNotEmpty;
    final hasPendingPaymentContactResume =
        pendingPay != null && (modeUnlockContact || pendingCanon);

    final firebaseLoggedOut = currentUser == null || uid.isEmpty;

    if (firebaseLoggedOut &&
        !(guestBuyerReady &&
            (origin != null || hasPendingPaymentContactResume))) {
      RuntimeFlowLogger.mark('CONTACT_RESTORE_DEFERRED_AUTH_NOT_READY', <String, Object?>{
        'uid': uid,
        'isAnonymous': isAnonymous,
        'mode': AppMode.currentMode.name,
        'activeCompanyId': AppMode.activeCompanyId.trim(),
        'guestPeekNonEmpty': guestPeek.isNotEmpty,
        'pendingGuestSidNonEmpty': pendingGuestSid.isNotEmpty,
        'originPresent': origin != null,
        'pendingPaymentContactResume': hasPendingPaymentContactResume,
        'source': 'auth_shell._attemptRestoreContactOrigin',
      });
      debugPrint(
        '[CONTACT_RESTORE_DEFERRED_AUTH_NOT_READY] uid=$uid mode=${AppMode.currentMode.name}',
      );
      return;
    }
    try {
      final bootstrapUid =
          (!firebaseLoggedOut && uid.isNotEmpty) ? uid : null;
      await ContactAccessController.instance.bootstrap(uid: bootstrapUid);
      debugPrint('[CONTACT_RESTORE_FROM_STORAGE] uid=${bootstrapUid ?? "guest"}');
      final originAfter = ContactAccessController.instance.pendingOrigin;
      debugPrint(
        '[CONTACT_RESTORE_FROM_STORAGE] origin=${originAfter?.toString() ?? 'null'}',
      );
      if (!mounted) return;
      debugPrint(
        '[PAYMENT_RETURN_CONTEXT_RESTORE] '
        'source=${originAfter?.source.name ?? 'none'} '
        'candidateId=${originAfter?.candidateId ?? ''} mode=auth_restore',
      );
      final restoreDisposition = await ContactAccessController.instance
          .restoreAfterPaywallExit(
            context,
            purchased: false,
            onExpandedRestore: (candidateId, canonicalId, candidateUid) async {
              debugPrint(
                '[CONTACT_RESTORE_AFTER_BOOTSTRAP] expanded candidateId=$candidateId canonicalId=${canonicalId ?? ''}',
              );
              await CandidateDetailsSheet.open(
                context,
                candidateId: candidateId,
                candidateUid: (candidateUid.isNotEmpty
                    ? candidateUid
                    : candidateId),
                canonicalCandidateId: (canonicalId ?? '').isNotEmpty
                    ? canonicalId
                    : null,
                testMode: false,
              );
            },
          );
      debugPrint(
        '[CONTACT_RESTORE_FROM_STORAGE] disposition=${restoreDisposition.name}',
      );
      if (restoreDisposition != ContactRestoreDisposition.noOrigin) {
        debugPrint(
          '[RESTORE_FLOW_UI_CONTEXT_REOPENED] disposition=${restoreDisposition.name}',
        );
      }
      if (restoreDisposition == ContactRestoreDisposition.noOrigin) {
        if (hasPendingPaymentContactResume) {
          RuntimeFlowLogger.mark(
            'CONTACT_RESTORE_FALLBACK_BLOCKED_FOR_PAYMENT_CONTEXT',
            <String, Object?>{
              'source': 'auth_shell._attemptRestoreContactOrigin',
              'modeUnlockContact': modeUnlockContact,
              'pendingCanon': pendingCanon,
              'guestPeekNonEmpty': guestPeek.isNotEmpty,
            },
          );
        } else {
          final snapshotCandidateId =
              (NavigationReturnSnapshot.pendingCandidateId ?? '').trim();
          final snapshotCandidateUid =
              (NavigationReturnSnapshot.pendingCandidateUid ?? '').trim();
          final snapshotCanonicalId =
              (NavigationReturnSnapshot.pendingCanonicalCandidateId ?? '')
                  .trim();
          if (snapshotCandidateId.isNotEmpty &&
              snapshotCandidateUid.isNotEmpty) {
            debugPrint(
              '[PAYMENT_RETURN_CONTEXT_RESTORE] '
              'source=navigation_snapshot candidateId=$snapshotCandidateId mode=auth_restore_fallback',
            );
            if (!mounted) return;
            await CandidateDetailsSheet.open(
              context,
              candidateId: snapshotCandidateId,
              candidateUid: snapshotCandidateUid,
              canonicalCandidateId: snapshotCanonicalId.isNotEmpty
                  ? snapshotCanonicalId
                  : null,
              testMode: false,
            );
            debugPrint(
              '[RESTORE_FLOW_UI_CONTEXT_REOPENED] disposition=navigation_snapshot',
            );
            NavigationReturnSnapshot.clearPendingDetails();
          }
        }
      }
    } catch (e) {
      debugPrint('[CONTACT_RESTORE_FROM_STORAGE] error $e');
    }
  }

  Future<bool> _tryRunDebugContactRestoreFromUrl() async {
    if (!_debugContactRestoreEnabledFromUrl || _debugContactRestoreTriggered) {
      return false;
    }

    final candidateId = _debugContactRestoreCandidateId;
    final canonicalId = _debugContactRestoreCanonicalId;
    final source = _debugContactRestoreSource;

    if (candidateId.isEmpty) {
      debugPrint(
        '[DEBUG_CONTACT_RESTORE_URL_ERROR] reason=missing_candidateId',
      );
      _debugContactRestoreTriggered = true;
      return true;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (!_isRealAuthenticatedUser(user)) {
      _debugContactRestorePending = true;
      debugPrint(
        '[DEBUG_CONTACT_RESTORE_URL_PENDING] reason=auth_not_ready '
        'candidateId=$candidateId canonicalId=$canonicalId sourceType=${source.name}',
      );
      return true;
    }

    final uid = user!.uid.trim();
    _debugContactRestorePending = false;
    _debugContactRestoreTriggered = true;
    debugPrint(
      '[DEBUG_CONTACT_RESTORE_URL_AUTH_READY] uid=$uid '
      'candidateId=$candidateId canonicalId=$canonicalId sourceType=${source.name}',
    );
    debugPrint(
      '[DEBUG_CONTACT_RESTORE_URL_TRIGGER] '
      'candidateId=$candidateId canonicalId=$canonicalId sourceType=${source.name}',
    );

    try {
      await ContactAccessController.instance.bootstrap(uid: uid);
      if (!mounted) return true;
      await ContactAccessController.instance.debugVerifyRestoreAfterPayment(
        context,
        candidateId: candidateId,
        canonicalCandidateId: canonicalId.isEmpty ? null : canonicalId,
        candidateUid: uid,
        source: source,
        onExpandedRestore: (candidateId, canonicalId, candidateUid) async {
          if (!mounted) return;
          await CandidateDetailsSheet.open(
            context,
            candidateId: candidateId,
            candidateUid: candidateUid.isNotEmpty ? candidateUid : candidateId,
            canonicalCandidateId: (canonicalId ?? '').isNotEmpty
                ? canonicalId
                : null,
            testMode: false,
          );
        },
      );
      debugPrint(
        '[DEBUG_CONTACT_RESTORE_URL_DONE] '
        'candidateId=$candidateId canonicalId=$canonicalId sourceType=${source.name}',
      );
    } catch (e) {
      debugPrint('[DEBUG_CONTACT_RESTORE_URL_ERROR] error=$e');
    }

    return true;
  }

  bool _isRealAuthenticatedUser(User? user) {
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return false;
    if (user?.isAnonymous ?? false) return false;
    if (uid.toLowerCase().startsWith('guest_')) return false;
    if (uid == 'guest') return false;
    return true;
  }

  bool _isHardAccountSwitch({
    required String previousUid,
    required String nextUid,
  }) {
    final prev = previousUid.trim();
    final next = nextUid.trim();
    if (prev.isEmpty || next.isEmpty || prev == next) return false;
    if (AuthGuard.isGuestLikeUid(prev) || AuthGuard.isGuestLikeUid(next)) {
      return false;
    }
    return true;
  }

  Future<void> _ensureProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _roleChecked = true);
      return;
    }
    try {
      await _profileRepo?.ensureProfileExists(user: user);
      if (!mounted) return;
      final needsRole = await _needsRoleSelect(user.uid);
      if (!mounted) return;
      if (!needsRole) await _restoreAccountMode(user.uid);
      final hasPendingCvIntent =
          (await AuthContinuationStore.instance.readPendingCvDraft()) != null;
      final hasPendingVacancyIntent =
          (await AuthContinuationStore.instance.readPendingVacancyDraft()) !=
          null;
      if (needsRole) {
        if (hasPendingCvIntent) {
          await _ensurePersonalProfileForVacancyIntent(uid: user.uid);
          RuntimeFlowLogger.mark('AUTH_ROLE_SELECT_SKIPPED', <String, Object?>{
            'uid': user.uid,
            'reason': 'cv_action_context',
          });
          if (mounted) setState(() => _roleChecked = true);
          return;
        }
        if (hasPendingVacancyIntent) {
          RuntimeFlowLogger.mark('AUTH_ROLE_SELECT_SKIPPED', <String, Object?>{
            'uid': user.uid,
            'reason': 'pending_vacancy_intent',
          });
          if (mounted) setState(() => _roleChecked = true);
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => const RoleSelectScreen()))
              .then((_) {
                if (mounted) setState(() => _roleChecked = true);
              });
        });
      } else {
        setState(() => _roleChecked = true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthShell] ensureProfile failed: $e');
      }
      if (mounted) setState(() => _roleChecked = true);
    }
  }

  Future<bool> _needsRoleSelect(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      return data == null ||
          (!(data['role']?.toString().trim().isNotEmpty ?? false) &&
              !((data['enabledProfiles'] as List?)?.isNotEmpty ?? false));
    } catch (e) {
      RuntimeFlowLogger.mark('CV_AUTH_CONTINUATION_DONE', <String, Object?>{
        'uid': uid,
        'error': 'needs_role_select_failed',
        'responseBody': e.toString(),
      });
      debugPrint('[AUTH_ROLE_SELECT_CHECK_FAILED] uid=$uid error=$e');
      return false;
    }
  }

  Future<void> _restoreAccountMode(String uid) async {
    RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_START', <String, Object?>{
      'uid': uid,
      'source': 'auth_shell_restore_account_mode',
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data();
      if (data == null) return;

      final profiles =
          (data['enabledProfiles'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      final hasBusiness = profiles.contains('business');
      final hasPersonal = profiles.contains('personal');
      final selectedProfileRaw =
          (data['selectedProfile'] ??
                  data['activeProfile'] ??
                  data['currentProfile'] ??
                  data['role'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();
      final requestedBusinessMode = selectedProfileRaw == 'business';
      String resolveBusinessCompanyId() {
        final business = data['business'] is Map
            ? Map<String, dynamic>.from(data['business'] as Map)
            : const <String, dynamic>{};
        for (final key in const <String>[
          'activeCompanyId',
          'companyId',
          'company_id',
          'id',
        ]) {
          final fromBusiness = (business[key] ?? '').toString().trim();
          if (fromBusiness.isNotEmpty) return fromBusiness;
          final fromRoot = (data[key] ?? '').toString().trim();
          if (fromRoot.isNotEmpty) return fromRoot;
        }
        return '';
      }
      Future<bool> tryActivateBusinessMode({
        required String reason,
      }) async {
        final companyId = resolveBusinessCompanyId();
        if (companyId.isNotEmpty) {
          await AppMode.setActiveCompanyId(companyId);
          _setAuthenticatedAppMode(
            mode: AccountMode.business,
            uid: uid,
            source: 'auth_shell._hydrateBusinessScope.tryActivateBusinessMode.ok',
          );
          RuntimeFlowLogger.mark('BUSINESS_SCOPE_RESOLVE', <String, Object?>{
            'status': 'ok',
            'companyId': companyId,
            'reason': reason,
          });
          debugPrint(
            '[BUSINESS_SCOPE_RESOLVE] status=ok companyId=$companyId reason=$reason',
          );
          return true;
        }
        await AppMode.setActiveCompanyId(null);
        _setAuthenticatedAppMode(
          mode: AccountMode.business,
          uid: uid,
          source: 'auth_shell._hydrateBusinessScope.tryActivateBusinessMode.missing_company',
        );
        RuntimeFlowLogger.mark(
          'BUSINESS_SCOPE_RESOLVE',
          <String, Object?>{
            'status': 'missing',
            'action': 'open_create_business_profile',
            'mode': 'business',
            'fallback': 'disabled',
            'reason': reason,
          },
        );
        debugPrint(
          '[BUSINESS_SCOPE_RESOLVE] status=missing action=open_create_business_profile reason=$reason',
        );
        return false;
      }

      if (hasBusiness && !hasPersonal) {
        final ok = await tryActivateBusinessMode(reason: 'business_only_profile');
        RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_OK', <String, Object?>{
          'uid': uid,
          'companyId': AppMode.activeCompanyId.trim(),
          'reason': ok
              ? 'business_only_profile'
              : 'business_only_profile_missing_company',
        });
        return;
      }

      if (hasPersonal && !hasBusiness) {
        _setAuthenticatedAppMode(
          mode: AccountMode.personal,
          uid: uid,
          source: 'auth_shell._hydrateBusinessScope.personal_only',
        );
        await AppMode.setActiveCompanyId(null);
        RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_OK', <String, Object?>{
          'uid': uid,
          'companyId': '',
          'reason': 'personal_only_profile',
        });
        return;
      }

      if (hasBusiness && hasPersonal && requestedBusinessMode) {
        final ok = await tryActivateBusinessMode(
          reason: 'requested_business_profile',
        );
        RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_OK', <String, Object?>{
          'uid': uid,
          'companyId': AppMode.activeCompanyId.trim(),
          'reason': ok
              ? 'requested_business_profile'
              : 'requested_business_profile_missing_company',
        });
        return;
      }

      if (hasPersonal) {
        _setAuthenticatedAppMode(
          mode: AccountMode.personal,
          uid: uid,
          source: 'auth_shell._hydrateBusinessScope.selected_personal',
        );
        await AppMode.setActiveCompanyId(null);
        RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_OK', <String, Object?>{
          'uid': uid,
          'companyId': '',
          'reason': 'selected_personal_profile',
        });
      } else {
        RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_OK', <String, Object?>{
          'uid': uid,
          'companyId': AppMode.activeCompanyId.trim(),
          'reason': 'no_business_switch_requested',
        });
      }

      if (kDebugMode) {
        debugPrint(
          '[AuthShell] skip forced mode restore; '
          'profiles=$profiles current=${AppMode.currentMode.name} selectedProfile=$selectedProfileRaw',
        );
      }
    } catch (e) {
      RuntimeFlowLogger.mark('BUSINESS_SCOPE_HYDRATE_FAILED', <String, Object?>{
        'uid': uid,
        'reason': 'restore_account_mode_exception',
        'error': e.toString(),
      });
      if (kDebugMode) {
        debugPrint('[AuthShell] restoreAccountMode failed: $e');
      }
    }
  }

  void _onTabTap(int index) {
    if (kDebugMode) {
      debugPrint('BottomNav -> switch tab $index');
    }
    NavigationReturnSnapshot.captureTab(index);
    setState(() {
      _index = index;
      _showBottomNav = true;
      _scrollAccumulator = 0;
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification.metrics.pixels <= 24) {
      if (!_showBottomNav) {
        setState(() => _showBottomNav = true);
      }
      _scrollAccumulator = 0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() < 0.5) return false;
      _scrollAccumulator += delta;

      if (_scrollAccumulator >= _scrollThreshold && _showBottomNav) {
        setState(() => _showBottomNav = false);
        _scrollAccumulator = 0;
      } else if (_scrollAccumulator <= -_scrollThreshold && !_showBottomNav) {
        setState(() => _showBottomNav = true);
        _scrollAccumulator = 0;
      }
      return false;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _scrollAccumulator = 0;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleChecked) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4A6FDB),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: Stack(
          children: [
            PageStorage(
              bucket: _pageStorageBucket,
              child: NotificationListener<FavoritesGoHomeNotification>(
                onNotification: (notification) {
                  if (_index != 0) {
                    setState(() => _index = 0);
                  }
                  return true;
                },
                child: IndexedStack(index: _index, children: _tabs),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: _showBottomNav ? Offset.zero : const Offset(0, 1.1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  opacity: _showBottomNav ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showBottomNav,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 12,
                            spreadRadius: 0,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: WorkaBottomNavigationBar(
                        currentIndex: _index,
                        onTap: _onTabTap,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
