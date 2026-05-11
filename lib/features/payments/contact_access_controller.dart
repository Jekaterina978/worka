import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/foundation.dart' as foundation show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/services/candidate_identity_resolver.dart';
import 'package:worka/services/runtime_flow_logger.dart';
import 'package:worka/theme/worka_colors.dart';

import 'analytics/monetization_analytics.dart';
import 'contact_unlock_store.dart';
import 'domain/models/credits_models.dart';
import 'models/employer_payment_models.dart';
import 'models/payment_product.dart';
import 'repository/payments_repository.dart';
import 'screens/contact_unlock_paywall_sheet.dart';
import 'contact_access_web_storage_helper.dart';
import 'services/payment_sheet_service.dart';
import 'services/stripe_payment_sheet_service.dart';
import 'widgets/credit_spend_confirmation_sheet.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_route_coordinator.dart';

part 'contact_access_models.dart';
part 'contact_access_state.dart';
part 'contact_access_resolution.dart';
part 'contact_access_contacts.dart';
part 'contact_access_entitlements.dart';

void _logDebug(String? message, {int? wrapWidth}) {
  if (!kDebugMode) return;
  foundation.debugPrint(message, wrapWidth: wrapWidth);
}

String _contactBuyerScopeSigFromParts({
  required bool isBusiness,
  required String uid,
  required String companyId,
}) {
  if (isBusiness) return 'business|$companyId';
  return 'personal|$uid';
}

({String ownerType, String ownerId}) _contactBuyerOwnerFromSig(String sig) {
  final s = sig.trim();
  if (s.isEmpty || s == 'guest') {
    return (ownerType: '', ownerId: '');
  }
  if (s.startsWith('guest|')) {
    final id = s.substring(6).trim();
    if (id.isEmpty) return (ownerType: '', ownerId: '');
    return (ownerType: 'guest', ownerId: id);
  }
  final sep = s.indexOf('|');
  if (sep <= 0 || sep >= s.length - 1) {
    return (ownerType: '', ownerId: '');
  }
  final kind = s.substring(0, sep).trim().toLowerCase();
  final id = s.substring(sep + 1).trim();
  if (kind == 'business') return (ownerType: 'business', ownerId: id);
  if (kind == 'personal') return (ownerType: 'personal', ownerId: id);
  return (ownerType: '', ownerId: '');
}

class ContactAccessController extends ChangeNotifier
    with
        ContactAccessStateMixin,
        ContactAccessResolutionMixin,
        ContactAccessContactsMixin,
        ContactAccessEntitlementsMixin {
  static const String _pendingUnlockPrefix = 'pending_unlock_candidate_';

  ContactAccessController({
    PaymentsRepository? repository,
    ContactUnlockStore? unlockStore,
    StripePaymentSheetService? stripePaymentSheetService,
  }) : _repository = repository ?? PaymentsRepository(),
       _unlockStore = unlockStore ?? ContactUnlockStore.instance,
       _stripeSheet = stripePaymentSheetService ?? StripePaymentSheetService();

  static final ContactAccessController instance = ContactAccessController();

  @override
  PaymentsRepository get repository => _repository;
  @override
  ContactUnlockStore get unlockStore => _unlockStore;
  @override
  String get pendingUnlockPrefix => _pendingUnlockPrefix;

  final PaymentsRepository _repository;
  final ContactUnlockStore _unlockStore;
  final StripePaymentSheetService _stripeSheet;
  final MonetizationAnalytics _analytics = MonetizationAnalytics.instance;
  bool _notifyQueued = false;

  /// Same buyer scope + concurrent [bootstrapForBuyerScope] → await one flight.
  Future<void>? _buyerScopeBootstrapOpFuture;
  String _buyerScopeBootstrapOpSig = '';

  // state fields moved to ContactAccessStateMixin
  String _pendingOriginStorageKey() =>
      _pendingOriginStorageKeyForScope(_uidScope);

  String _pendingOriginStorageKeyForScope(String scope) =>
      ContactAccessWebStorageHelper.pendingOriginStorageKey(
        prefix: pendingUnlockPrefix,
        scope: scope,
      );
  String? pendingUnlockCandidateIdForUid(String uid) {
    return ContactAccessWebStorageHelper.pendingUnlockCandidateIdForUid(
      prefix: pendingUnlockPrefix,
      uid: uid,
    );
  }

  void setPendingUnlockIntentForUid(String uid, String candidateKey) {
    ContactAccessWebStorageHelper.setPendingUnlockIntentForUid(
      prefix: pendingUnlockPrefix,
      uid: uid,
      candidateKey: candidateKey,
    );
  }

  void clearPendingUnlockIntentForUid(String uid) {
    ContactAccessWebStorageHelper.clearPendingUnlockIntentForUid(
      prefix: pendingUnlockPrefix,
      uid: uid,
    );
  }

  List<CreditPack> getCreditPacks() {
    final packs = PaymentProducts.creditPackages;
    return packs
        .map((p) {
          final contacts = p.credits ?? _contactsFromTitle(p.title);
          return CreditPack(
            id: p.id,
            contacts: contacts,
            cents: p.cents,
            title: p.title,
            subtitle: p.subtitle,
            isMostPopular: p.isMostPopular,
            isBestValue: p.isBestValue,
          );
        })
        .toList(growable: false);
  }

  /// Resolves the current contact surface (guest / personal / business).
  /// Guest is a real, supported buyer scope (backed by guest session id and
  /// `buyer_guest_id` rows in `candidate_contact_unlocks`).
  ({bool isGuest, bool isBusiness, String uid, String activeCompanyId, String guestSessionId, String mode})
  _resolveContactSurface() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final activeCompanyId = app_mode.AppMode.activeCompanyId.trim();
    final isAnonymous = user?.isAnonymous ?? false;
    final isGuestLike =
        uid.isEmpty || uid == 'guest' || uid.toLowerCase().startsWith('guest_');
    final isGuest =
        !isBiz && (user == null || isAnonymous || isGuestLike);
    // Persisted id only — mint allowed from AuthShell init / paywall / checkout,
    // never implicitly here (restore & telemetry stay aligned).
    final guestSessionId = isGuest
        ? _repository.peekGuestSessionId().trim()
        : '';
    return (
      isGuest: isGuest,
      isBusiness: isBiz,
      uid: uid,
      activeCompanyId: activeCompanyId,
      guestSessionId: guestSessionId,
      mode: app_mode.AppMode.currentMode.name,
    );
  }

  bool _isGuestSurface() => _resolveContactSurface().isGuest;

  ({bool isValid, String reason, String uid, String activeCompanyId, String mode, bool isGuest, String guestSessionId})
  _validateBuyerScopeOrBlocked({
    required String source,
    bool silent = false,
  }) {
    final s = _resolveContactSurface();
    final user = FirebaseAuth.instance.currentUser;
    final hasUser = user != null;
    final isAnonymous = user?.isAnonymous ?? false;
    final authReadyForContactScope = s.isGuest
        ? s.guestSessionId.isNotEmpty
        : (!isAnonymous &&
            s.uid.isNotEmpty &&
            (!s.isBusiness || s.activeCompanyId.isNotEmpty));
    if (!silent) {
      RuntimeFlowLogger.mark('AUTH_READY_STATE_RESOLVED', <String, Object?>{
        'uid': s.uid,
        'hasUser': hasUser,
        'isAnonymous': isAnonymous,
        'appMode': s.mode,
        'activeCompanyId': s.activeCompanyId,
        'isGuest': s.isGuest,
        'guestSessionId': s.guestSessionId,
        'authReadyForContactScope': authReadyForContactScope,
        'reason': source,
        'source': 'contact_access_controller._validateBuyerScopeOrBlocked',
      });
    }
    if (s.isBusiness && s.activeCompanyId.isEmpty) {
      if (!silent) {
        RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_BLOCKED', <String, Object?>{
          'mode': s.mode,
          'uid': s.uid,
          'activeCompanyId': s.activeCompanyId,
          'reason': 'missing_active_company_id',
          'source': source,
        });
      }
      return (
        isValid: false,
        reason: 'missing_active_company_id',
        uid: s.uid,
        activeCompanyId: s.activeCompanyId,
        mode: s.mode,
        isGuest: false,
        guestSessionId: '',
      );
    }
    if (s.isGuest && s.guestSessionId.isEmpty) {
      if (!silent) {
        RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_BLOCKED', <String, Object?>{
          'mode': s.mode,
          'reason': 'guest_session_unavailable',
          'source': source,
        });
      }
      return (
        isValid: false,
        reason: 'guest_session_unavailable',
        uid: s.uid,
        activeCompanyId: s.activeCompanyId,
        mode: s.mode,
        isGuest: true,
        guestSessionId: '',
      );
    }
    return (
      isValid: true,
      reason: '',
      uid: s.uid,
      activeCompanyId: s.activeCompanyId,
      mode: s.mode,
      isGuest: s.isGuest,
      guestSessionId: s.guestSessionId,
    );
  }

  ({bool isValid, String reason}) ensureContactBuyerScopeReady({
    required String source,
    bool silent = false,
  }) {
    final validity = _validateBuyerScopeOrBlocked(
      source: source,
      silent: silent,
    );
    return (isValid: validity.isValid, reason: validity.reason);
  }

  String _computeBuyerScopeSig({bool silent = false}) {
    final validity = _validateBuyerScopeOrBlocked(
      source: 'contact_access_controller._computeBuyerScopeSig',
      silent: silent,
    );
    if (!validity.isValid) return '';
    if (validity.isGuest) {
      return 'guest|${validity.guestSessionId}';
    }
    return _contactBuyerScopeSigFromParts(
      isBusiness: validity.mode == 'business',
      uid: validity.uid,
      companyId: validity.activeCompanyId,
    );
  }

  ({String buyerOwnerType, String buyerOwnerId, String buyerSig}) resolveContactBuyerScope() {
    final sig = _computeBuyerScopeSig(silent: false);
    final owner = _contactBuyerOwnerFromSig(sig);
    return (
      buyerOwnerType: owner.ownerType,
      buyerOwnerId: owner.ownerId,
      buyerSig: sig,
    );
  }

  /// Public buyer-scope signature for dependency gates (`personal|…`, `business|…`, `guest`).
  String computeBuyerScopeSig({bool silent = false}) =>
      _computeBuyerScopeSig(silent: silent);

  /// Compact explanation when UI shows paywall with zero credits / no entitlement.
  /// Does **not** mutate access — diagnostic only.
  String describeContactPaywallDebugReason({
    required String resolvedCandidateKey,
  }) {
    final parts = <String>[];
    final rk = resolvedCandidateKey.trim();
    final entitled = rk.isNotEmpty && hasAccessToCandidateContact(rk);

    if (entitled) {
      return 'has_entitlement';
    }
    if (_walletRefreshError != null) {
      parts.add('wallet_refresh_failed');
    }
    if (_creditsBalance <= 0 && _walletRefreshError == null) {
      parts.add('no_wallet_credits_in_current_buyer_scope');
    }
    if (rk.isEmpty) {
      parts.add('missing_resolved_candidate_key');
    } else if (_serverUnlockedCandidateIds.isEmpty) {
      parts.add('backend_returned_empty_access_list');
    } else {
      parts.add('no_unlock_row_in_current_buyer_scope');
    }
    return parts.isEmpty ? 'n/a' : parts.join('; ');
  }

  /// Explicit backend sync for the **current** buyer scope (personal vs business).
  /// Call when opening candidate surfaces so wallet + unlock list match headers.
  Future<void> bootstrapForBuyerScope({required String source}) async {
    final buyerSig = _computeBuyerScopeSig();
    while (_buyerScopeBootstrapOpFuture != null &&
        _buyerScopeBootstrapOpSig != buyerSig) {
      await _buyerScopeBootstrapOpFuture;
    }
    if (_buyerScopeBootstrapOpFuture != null &&
        _buyerScopeBootstrapOpSig == buyerSig) {
      return _buyerScopeBootstrapOpFuture!;
    }
    final fut = _bootstrapForBuyerScopeOnce(source: source);
    _buyerScopeBootstrapOpFuture = fut;
    _buyerScopeBootstrapOpSig = buyerSig;
    try {
      await fut;
    } finally {
      if (identical(_buyerScopeBootstrapOpFuture, fut)) {
        _buyerScopeBootstrapOpFuture = null;
        _buyerScopeBootstrapOpSig = '';
      }
    }
  }

  Future<void> _bootstrapForBuyerScopeOnce({required String source}) async {
    final validity = _validateBuyerScopeOrBlocked(
      source: '${source}_bootstrapForBuyerScope',
    );
    if (!validity.isValid) return;
    final user = FirebaseAuth.instance.currentUser;
    final uid = validity.uid;
    final buyerSig = _computeBuyerScopeSig();
    if (buyerSig.isEmpty) return;
    final prevSig = _buyerScopeBootstrapSig;
    final prevParsed = _contactBuyerOwnerFromSig(prevSig);
    final isBiz = validity.mode == 'business';
    final ownerIdNow = validity.isGuest
        ? validity.guestSessionId
        : (isBiz ? validity.activeCompanyId : uid);
    final ownerTypeNow =
        validity.isGuest ? 'guest' : (isBiz ? 'business' : 'personal');
    final staleReason = !_bootstrapped
        ? 'never_bootstrapped'
        : (prevSig != buyerSig
              ? 'buyer_scope_mismatch'
              : !_unlocksHydratedForScope
              ? 'unlocks_not_hydrated'
              : 'candidate_surface_refresh');

    RuntimeFlowLogger.mark('CONTACT_BOOTSTRAP_START', <String, Object?>{
      'source': source,
      'mode': app_mode.AppMode.currentMode.name,
      'ownerType': ownerTypeNow,
      'ownerId': ownerIdNow,
      'uid': uid,
      'companyId': app_mode.AppMode.activeCompanyId.trim(),
      'previousOwnerType': prevParsed.ownerType,
      'previousOwnerId': prevParsed.ownerId,
      'bootstrapReadyBefore':
          _bootstrapped && _unlocksHydratedForScope && prevSig == buyerSig,
      'staleReason': staleReason,
      'buyerSigBefore': prevSig,
      'buyerSigNow': buyerSig,
    });

    await bootstrap(uid: user?.uid);

    RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_RESOLVE', <String, Object?>{
      'source': '${source}_bootstrapForBuyerScope',
      'buyerOwnerType': ownerTypeNow,
      'buyerOwnerId': ownerIdNow,
      'buyerSig': buyerSig,
      'uid': uid,
      'companyId': app_mode.AppMode.activeCompanyId.trim(),
      'mode': app_mode.AppMode.currentMode.name,
    });

    await refreshWallet();
    await refreshUnlocked(force: true);

    RuntimeFlowLogger.mark('CONTACT_BOOTSTRAP_DONE', <String, Object?>{
      'ownerType': ownerTypeNow,
      'ownerId': ownerIdNow,
      'credits': _creditsBalance,
      'unlockedCount': _serverUnlockedCandidateIds.length,
      'bootstrapReady': isBootstrapReadyForCurrentScope,
      'source': source,
      'buyerSig': buyerSig,
    });
  }

  /// Whether contact wallet + unlock list are synced for the current buyer scope.
  bool get isBootstrapReadyForCurrentScope {
    final sig = _computeBuyerScopeSig(silent: true);
    if (sig.isEmpty) return false;
    return _bootstrapped &&
        _unlocksHydratedForScope &&
        _buyerScopeBootstrapSig.isNotEmpty &&
        _buyerScopeBootstrapSig == sig;
  }

  /// Lightweight entry for list/card widgets: refreshes buyer scope only when stale,
  /// coalescing parallel callers into one [bootstrapForBuyerScope] flight.
  Future<void> bootstrapForBuyerScopeIfStale({required String source}) async {
    final scopeReady = ensureContactBuyerScopeReady(
      source: '${source}_bootstrapForBuyerScopeIfStale',
    );
    if (!scopeReady.isValid) {
      RuntimeFlowLogger.mark('CONTACT_BOOTSTRAP_SKIPPED', <String, Object?>{
        'reason': 'scope_not_ready',
        'source': source,
        'buyerSig': _computeBuyerScopeSig(),
      });
      return;
    }
    if (isBootstrapReadyForCurrentScope) {
      RuntimeFlowLogger.mark('CONTACT_BOOTSTRAP_SKIPPED', <String, Object?>{
        'reason': 'scope_already_ready',
        'source': source,
        'buyerSig': _computeBuyerScopeSig(),
      });
      return;
    }
    final hadLeader = _federatedBuyerScopeBootstrapFuture != null;
    _federatedBuyerScopeBootstrapFuture ??=
        bootstrapForBuyerScope(source: source);
    final future = _federatedBuyerScopeBootstrapFuture!;
    if (hadLeader) {
      RuntimeFlowLogger.mark('CONTACT_BOOTSTRAP_SKIPPED', <String, Object?>{
        'reason': 'join_in_flight_buyer_scope_refresh',
        'source': source,
      });
    }
    try {
      await future;
    } finally {
      if (identical(_federatedBuyerScopeBootstrapFuture, future)) {
        _federatedBuyerScopeBootstrapFuture = null;
      }
    }
  }

  Future<CandidateContact?> ensureLoadedContactForCandidate(
    String candidateId,
  ) async {
    final rawInput = candidateId.trim();
    if (rawInput.isEmpty) return null;
    final id = _effectiveContactStateKey(rawInput);
    if (id.isEmpty) return null;
    await bootstrap(uid: FirebaseAuth.instance.currentUser?.uid);
    var current = stateForCandidateKey(rawInput);
    if (current.contact != null) return current.contact;

    final pendingJoin = _contactLoadInFlightByCandidate[id];
    if (pendingJoin != null) return pendingJoin;

    bool forcedRefreshDone = false;
    if (!current.hasEntitlement) {
      final needForce = !_unlocksHydratedForScope;
      await refreshUnlocked(force: needForce);
      forcedRefreshDone = needForce;
    }
    if (!hasAccessToCandidateContact(rawInput)) {
      if (!forcedRefreshDone) {
        await refreshUnlocked(force: true);
      }
      if (!hasAccessToCandidateContact(rawInput)) {
        RuntimeFlowLogger.mark('CONTACT_ENTITLEMENT_READ', <String, Object?>{
          'candidateId': rawInput,
          'canonicalCandidateId': id,
          'resolvedKey': id,
          'unlockedFound': false,
          'uidScope': _uidScope,
        });
        return null;
      }
    }
    RuntimeFlowLogger.mark('CONTACT_ENTITLEMENT_READ', <String, Object?>{
      'candidateId': rawInput,
      'canonicalCandidateId': id,
      'resolvedKey': id,
      'unlockedFound': true,
      'uidScope': _uidScope,
    });

    final pendingAfterUnlockList = _contactLoadInFlightByCandidate[id];
    if (pendingAfterUnlockList != null) return pendingAfterUnlockList;

    current = stateForCandidateKey(rawInput);
    if (current.contact != null) return current.contact;

    RuntimeFlowLogger.mark('CONTACT_ENSURE_LOAD_START', <String, Object?>{
      'candidateId': rawInput,
      'canonicalCandidateId': id,
      'resolvedKey': id,
      'uidScope': _uidScope,
      'hasAccess': hasAccessToCandidateContact(rawInput),
      'contactLoaded': contactForCandidate(rawInput) != null,
      'endpoint': '/employer/contacts/:id',
    });
    _logDebug(
      '[CONTACT_ENSURE_START] raw=$rawInput resolved=$id ctrlHash=${identityHashCode(this)} state=${stateForCandidateKey(rawInput)}',
    );

    final loadingBase =
        stateForCandidateKey(rawInput).copyWith(
      isLoadingContact: true,
      clearError: true,
    );
    _stateByKey[id] = loadingBase;
    final aliases = _canonicalToCandidates[id];
    if (aliases != null) {
      for (final cvId in aliases) {
        final p = _stateByKey[cvId] ?? CandidateContactAccessState.initial();
        _stateByKey[cvId] = p.copyWith(isLoadingContact: true, clearError: true);
      }
    }
    _safeNotify();

    _logDebug('[contact_debug][load:start] candidateId=$id');
    final future = _loadUnlockedContactInternal(id);
    _contactLoadInFlightByCandidate[id] = future;
    return future
        .then((contact) {
          RuntimeFlowLogger.mark(
            'CONTACT_ENSURE_LOAD_SUCCESS',
            <String, Object?>{
              'candidateId': rawInput,
              'canonicalCandidateId': id,
              'resolvedKey': id,
              'hasContact': contact != null,
              'uidScope': _uidScope,
            },
          );
          return contact;
        })
        .catchError((Object e) {
          RuntimeFlowLogger.mark(
            'CONTACT_ENSURE_LOAD_FAILED',
            <String, Object?>{
              'candidateId': rawInput,
              'canonicalCandidateId': id,
              'resolvedKey': id,
              'error': e.toString(),
              'uidScope': _uidScope,
            },
          );
          throw e;
        })
        .whenComplete(() {
          _contactLoadInFlightByCandidate.remove(id);
          _logDebug(
            '[CONTACT_ENSURE_DONE] key=$id hasContact=${contactForCandidate(rawInput) != null}',
          );
        });
  }

  Future<void> bootstrap({String? uid}) async {
    final scopeReady = ensureContactBuyerScopeReady(
      source: 'contact_access_controller.bootstrap',
    );
    if (!scopeReady.isValid) {
      final user = FirebaseAuth.instance.currentUser;
      final authUid = (user?.uid ?? '').trim();
      RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_BLOCKED', <String, Object?>{
        'mode': app_mode.AppMode.currentMode.name,
        'uid': authUid,
        'activeCompanyId': app_mode.AppMode.activeCompanyId.trim(),
        'reason': 'bootstrap_scope_not_ready_${scopeReady.reason}',
        'source': 'contact_access_controller.bootstrap',
      });
      return;
    }
    final isGuest = _isGuestSurface();
    if (_isBootstrapping) {
      // Wait for in-flight bootstrap to avoid racing with unhydrated state.
      if (_bootstrapFuture != null) {
        await _bootstrapFuture;
      }
      return;
    }
    _isBootstrapping = true;
    final completer = Completer<void>();
    _bootstrapFuture = completer.future;
    _safeNotify();
    final next = _normalizeUid(uid);
    final buyerSigNow = _computeBuyerScopeSig();
    // Hard safeguard: once in auth scope, never downgrade to guest/null.
    if (_uidScope != 'guest' && next == 'guest') {
      _logDebug(
        '[CONTACT_BOOTSTRAP] skip guest/null bootstrap after auth current=$_uidScope next=$next',
      );
      _isBootstrapping = false;
      return;
    }
    final buyerScopeSynced =
        _buyerScopeBootstrapSig.isNotEmpty &&
        _buyerScopeBootstrapSig == buyerSigNow;
    if (_bootstrapped &&
        next == _uidScope &&
        _unlocksHydratedForScope &&
        buyerScopeSynced) {
      _logDebug(
        '[CONTACT_BOOTSTRAP_SKIP] reason=already_hydrated scope=$next '
        'unlocksHydrated=$_unlocksHydratedForScope buyerSig=$buyerSigNow',
      );
      _isBootstrapping = false;
      _hasBootstrapAttempted = true;
      _safeNotify();
      return;
    }
    try {
      if (_uidScope != next) {
        _stateByKey.clear();
        _serverUnlockedCandidateIds.clear();
        _accessKeyResolveLogged.clear();
        _inFlightByCandidate.clear();
        _spendInFlightByCandidate.clear();
        _contactLoadInFlightByCandidate.clear();
        _creditsBalance = 0;
        _wallet = null;
        _purchaseInFlight = null;
        _unlocksHydratedForScope = false;
        // Clear any pending unlock intent bound to previous auth scope.
        ContactAccessWebStorageHelper.clearPendingUnlockIntentForScope(
          prefix: _pendingUnlockPrefix,
          scope: _uidScope,
        );
        if (_pendingOriginContext != null) {
          _logDebug(
            '[CONTACT_RESTORE_CLEAR] reason=auth_scope_change prevScope=$_uidScope nextScope=$next candidateId=${_pendingOriginContext?.candidateId ?? ''} canonicalId=${_pendingOriginContext?.canonicalId ?? ''}',
          );
        }
        _pendingOriginContext = null;
        _buyerScopeBootstrapSig = '';
        _federatedBuyerScopeBootstrapFuture = null;
      }
      _uidScope = next;
      ContactAccessWebStorageHelper.clearPendingUnlockIntentForScope(
        prefix: _pendingUnlockPrefix,
        scope: _uidScope,
      );
      _logDebug(
        '[CONTACT_BOOTSTRAP] start uidScope=$_uidScope ctrlHash=${identityHashCode(this)}',
      );
      // Re-hydrate origin written before bootstrap (e.g. paywall open); do not
      // leave memory null while web storage still holds the pending context.
      _pendingOriginContext = _loadPendingOriginFromStorage();
      await _unlockStore.load(uid: uid);
      try {
        _logDebug(
          '[CONTACT_BOOTSTRAP_HYDRATE_UNLOCKS_BEGIN] scope=$_uidScope',
        );
        final ids = await _repository.getUnlockedCandidateIds();
        _serverUnlockedCandidateIds
          ..clear()
          ..addAll(ids);
        _unlocksHydratedForScope = true;
        _logDebug(
          '[CONTACT_BOOTSTRAP_HYDRATE_UNLOCKS_DONE] scope=$_uidScope count=${_serverUnlockedCandidateIds.length}',
        );
      } catch (e) {
        _logDebug('[CONTACT_BOOTSTRAP] hydrate unlocked failed $e');
        _unlocksHydratedForScope = false;
      }
      if (isGuest) {
        _walletRefreshError = null;
        _creditsBalance = 0;
        _logDebug('[CREDITS_REFRESH] skipped reason=guest_surface');
      } else {
        try {
          await _refreshAuthoritativeCreditsState(reason: 'bootstrap');
        } catch (e) {
          _walletRefreshError = e;
          _logDebug('[CREDITS_REFRESH] reason=bootstrap failed error=$e');
        }
      }
      _bootstrapped = true;
      if (_unlocksHydratedForScope) {
        _buyerScopeBootstrapSig = _computeBuyerScopeSig();
      }
      _bootstrapError = null;
      _logDebug(
        '[CONTACT_BOOTSTRAP] success uidScope=$_uidScope ctrlHash=${identityHashCode(this)}',
      );
    } catch (e, st) {
      _bootstrapError = e;
      _logDebug(
        '[CONTACT_BOOTSTRAP] fail uidScope=$_uidScope error=$e stack=$st',
      );
    } finally {
      _isBootstrapping = false;
      _hasBootstrapAttempted = true;
      _safeNotify();
      if (!completer.isCompleted) {
        completer.complete();
      }
      _bootstrapFuture = null;
    }
  }

  Future<EmployerWallet> getWallet({String? uid}) async {
    try {
      final wallet = await _repository.getAuthoritativeEmployerWalletState();
      await _applyAuthoritativeWalletState(
        wallet,
        uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
      );
      _walletRefreshError = null;
      _logDebug(
        '[CREDITS_REFRESH] reason=get_wallet credits=${wallet.balance} unlocked=${wallet.unlockedCandidateIds.length}',
      );
      return _wallet!;
    } catch (e) {
      _walletRefreshError = e;
      final fallback = EmployerWallet(
        uid: _normalizeUid(uid),
        balance: _creditsBalance,
        unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
        fetchedAt: DateTime.now(),
      );
      _wallet = fallback;
      _logDebug(
        '[CREDITS_REFRESH] reason=get_wallet_fallback credits=${fallback.balance} error=$e',
      );
      return fallback;
    }
  }

  // _normalizeUid provided by ContactAccessStateMixin

  static int _contactsFromTitle(String title) {
    final m = RegExp(r'(\\d+)').firstMatch(title);
    return int.tryParse(m?.group(1) ?? '') ?? 1;
  }

  ContactUnlockOriginContext? _loadPendingOriginFromStorage() {
    final payload = ContactAccessWebStorageHelper.loadPendingOriginFromStorage(
      _pendingOriginStorageKey(),
    );
    if (payload == null) return null;
    final source = payload.source == 'expandedCandidateCard'
        ? ContactUnlockSource.expandedCandidateCard
        : ContactUnlockSource.compactCard;
    return ContactUnlockOriginContext(
      source: source,
      candidateId: payload.candidateId,
      candidateUid: payload.candidateUid,
      canonicalId: payload.canonicalId,
      resolvedKey: payload.resolvedKey,
    );
  }

  void setPendingOrigin(ContactUnlockOriginContext origin) {
    _pendingOriginContext = origin;
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final ownerId =
        isBiz ? app_mode.AppMode.activeCompanyId.trim() : uid;
    RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CAPTURE', <String, Object?>{
      'source': origin.source.name,
      'candidateId': origin.candidateId,
      'canonicalCandidateId': origin.canonicalId ?? '',
      'resolvedKey': origin.resolvedKey ?? '',
      'mode': app_mode.AppMode.currentMode.name,
      'ownerType': isBiz ? 'company' : 'user',
      'ownerId': ownerId,
    });
    _flushPendingOriginToStorage(origin);
  }

  /// Restores in-memory pending origin from web storage when it was cleared
  /// during [bootstrap] (same uid) or never hydrated — required so auth-before-
  /// payment capture can read [pendingOrigin] after `setPendingOrigin` + `bootstrap`.
  void hydratePendingOriginFromStorageIfNull() {
    if (_pendingOriginContext != null) return;
    final loaded = _loadPendingOriginFromStorage();
    if (loaded == null) return;
    _pendingOriginContext = loaded;
    _logDebug(
      '[CONTACT_ORIGIN_HYDRATE] source=${loaded.source.name} candidateId=${loaded.candidateId} canonicalId=${loaded.canonicalId ?? ''}',
    );
  }

  Future<void> flushPendingOriginToStorage() async {
    final origin = _pendingOriginContext;
    if (origin == null) return;
    _flushPendingOriginToStorage(origin);
  }

  String? debugPeekPendingOriginStorageRaw() {
    return ContactAccessWebStorageHelper.debugPeekPendingOriginStorageRaw(
      _pendingOriginStorageKey(),
    );
  }

  void navTrace(String label, Map<String, dynamic> payload) {
    try {
      _logDebug('[NAV_TRACE][$label] ${json.encode(payload)}');
    } catch (_) {
      _logDebug('[NAV_TRACE][$label] $payload');
    }
  }

  void _flushPendingOriginToStorage(ContactUnlockOriginContext origin) {
    ContactAccessWebStorageHelper.flushPendingOriginToStorage(
      _pendingOriginStorageKey(),
      ContactAccessPendingOriginPayload(
        source: origin.source.name,
        candidateId: origin.candidateId,
        candidateUid: origin.candidateUid ?? '',
        canonicalId: origin.canonicalId ?? '',
        resolvedKey: origin.resolvedKey ?? '',
      ),
    );
    _logDebug(
      '[CONTACT_ORIGIN_WRITE] source=${origin.source.name} candidateId=${origin.candidateId} candidateUid=${origin.candidateUid ?? ''} canonicalId=${origin.canonicalId ?? ''} resolvedKey=${origin.resolvedKey ?? ''}',
    );
  }

  void clearPendingOrigin({String reason = 'unspecified'}) {
    _logDebug('[CONTACT_ORIGIN_CLEAR_CHECK] point=$reason');
    if (_pendingOriginContext != null) {
      navTrace('CONTACT_FLOW_SOURCE_CLEAR', {
        'sourceType': _pendingOriginContext!.source.name,
        'candidateId': _pendingOriginContext!.candidateId,
        'reason': reason,
      });
    }
    _pendingOriginContext = null;
    ContactAccessWebStorageHelper.removeStorageKey(_pendingOriginStorageKey());
    _logDebug('[CONTACT_ORIGIN_CLEAR] after_restore_only');
  }

  void _safeNotify() {
    if (_notifyQueued) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      _notifyQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyQueued = false;
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> ensureContactLoaded(String resolvedKey) async {
    await fetchContactForCandidate(resolvedKey);
  }

  Future<void> fetchContactForCandidate(String resolvedKey) async {
    final key = _effectiveContactStateKey(resolvedKey);
    if (key.isEmpty) return;
    final inFlight = _contactLoadInFlightByCandidate[key];
    if (inFlight != null) {
      await inFlight;
      return;
    }
    _logDebug('[CONTACT_FETCH_BEGIN] key=$key');
    try {
      final contact = await ensureLoadedContactForCandidate(key);
      _logDebug('[CONTACT_FETCH_DONE] key=$key success=${contact != null}');
    } catch (e) {
      _logDebug('[CONTACT_FETCH_DONE] key=$key success=false error=$e');
    }
  }

  /// Unlock entitlement exists **and** employer contacts payload was loaded from
  /// a successful `/employer/contacts/:id` read (cached in controller state).
  bool hasConfirmedCandidateContact(String candidateId) {
    final s = stateForCandidateKey(candidateId);
    return s.hasEntitlement && s.contact != null;
  }

  void _showUnlockFeedback(
    BuildContext context, {
    required String message,
    bool success = true,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? const Color(0xFF1F8A4C)
            : WorkaColors.textDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _confirmCreditSpend(
    BuildContext context, {
    required int creditsBefore,
  }) async {
    if (!context.mounted) return false;
    final approved = await showCreditSpendConfirmationSheet(
      context,
      creditsBefore: creditsBefore,
    );
    return approved == true;
  }

  Future<void> refreshWallet() async {
    if (_isGuestSurface()) {
      _walletRefreshError = null;
      _creditsBalance = 0;
      _wallet = EmployerWallet(
        uid: 'guest',
        balance: 0,
        unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
        fetchedAt: DateTime.now(),
      );
      RuntimeFlowLogger.mark('CONTACT_WALLET_REFRESH_RESULT', <String, Object?>{
        'ownerType': 'guest',
        'ownerId': _resolveContactSurface().guestSessionId,
        'credits': 0,
        'skipped': 'guest_wallet_not_supported',
      });
      _safeNotify();
      return;
    }
    final next = _walletRefreshTail.then((_) => _refreshWalletOnce());
    _walletRefreshTail = next.catchError((_, __) {});
    return next;
  }

  Future<void> _refreshWalletOnce() async {
    await getWallet(uid: FirebaseAuth.instance.currentUser?.uid);
    _lastWalletRefreshAt = DateTime.now();
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final ownerId = isBiz ? app_mode.AppMode.activeCompanyId.trim() : uid;
    RuntimeFlowLogger.mark('CONTACT_WALLET_REFRESH_RESULT', <String, Object?>{
      'ownerType': isBiz ? 'company' : 'user',
      'ownerId': ownerId,
      'credits': _creditsBalance,
    });
  }

  Future<Set<String>> getUnlockedCandidateIds({String? uid}) async {
    await bootstrap(uid: uid ?? FirebaseAuth.instance.currentUser?.uid);
    await refreshUnlocked(force: true);
    _logDebug(
      '[CONTACT_REFRESH_DONE] ctrlHash=${identityHashCode(this)} unlocked=${_serverUnlockedCandidateIds.length}',
    );
    return Set<String>.from(_serverUnlockedCandidateIds);
  }

  Future<void> refreshUnlocked({bool force = false}) async {
    final capturedForce = force;
    final next = _unlockRefreshTail.then(
      (_) => _refreshUnlockedOnce(force: capturedForce),
    );
    _unlockRefreshTail = next.catchError((_, __) {});
    return next;
  }

  Future<void> _refreshUnlockedOnce({required bool force}) async {
    final validity = _validateBuyerScopeOrBlocked(
      source: 'contact_access_controller.refreshUnlocked',
    );
    if (!validity.isValid) return;
    final uid = validity.uid;
    final isBiz = validity.mode == 'business';
    final ownerIdForLog = validity.isGuest
        ? validity.guestSessionId
        : (isBiz ? validity.activeCompanyId : uid);
    final ownerTypeLog =
        validity.isGuest ? 'guest' : (isBiz ? 'business' : 'personal');
    if (!force && _unlocksHydratedForScope) {
      _logDebug('[UNLOCK_REFRESH_START] scope=$uid skip=hydrated force=$force');
      RuntimeFlowLogger.mark('CONTACT_ACCESS_CHECK_RESULT', <String, Object?>{
        'skipped': true,
        'reason': 'already_hydrated',
        'ownerType': ownerTypeLog,
        'ownerId': ownerIdForLog,
        'unlockedCount': _serverUnlockedCandidateIds.length,
        'source': 'refreshUnlocked',
      });
      return;
    }
    final scope = _uidScope;
    final started = DateTime.now();
    _logDebug('[UNLOCK_REFRESH_START] scope=$scope force=$force');
    _logDebug('[CONTACT_REFRESH_FORCE] scope=$scope force=$force start');
    try {
      RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_RESOLVE', <String, Object?>{
        'source': 'contact_access_controller.refreshUnlocked',
        'buyerOwnerType': ownerTypeLog,
        'buyerOwnerId': ownerIdForLog,
        'buyerSig': _computeBuyerScopeSig(),
        'uid': uid,
        'companyId': app_mode.AppMode.activeCompanyId.trim(),
        'mode': app_mode.AppMode.currentMode.name,
      });
      final ids = await _repository.getUnlockedCandidateIds();
      applyUnlockedIds(Set<String>.from(ids));
      _unlocksHydratedForScope = true;
      _bootstrapped = true;
      _lastAccessRefreshAt = DateTime.now();
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      _logDebug(
        '[CONTACT_REFRESH_FORCE] scope=$scope force=$force unlocked=${_serverUnlockedCandidateIds.length} durationMs=$durationMs',
      );
      RuntimeFlowLogger.mark('CONTACT_ACCESS_CHECK_RESULT', <String, Object?>{
        'skipped': false,
        'unlockedCount': _serverUnlockedCandidateIds.length,
        'ownerType': ownerTypeLog,
        'ownerId': ownerIdForLog,
        'uid': uid,
        'source': 'refreshUnlocked',
      });
    } catch (e) {
      _logDebug('[CONTACT_REFRESH_FORCE] scope=$scope failed $e');
      RuntimeFlowLogger.mark('CONTACT_ACCESS_CHECK_RESULT', <String, Object?>{
        'skipped': false,
        'ok': false,
        'error': e.toString(),
        'unlockedCount': _serverUnlockedCandidateIds.length,
        'source': 'refreshUnlocked',
      });
    } finally {
      _safeNotify();
    }
  }

  Future<bool> syncHasAccessToCandidateContact(String candidateId) async {
    await getUnlockedCandidateIds(uid: FirebaseAuth.instance.currentUser?.uid);
    return hasAccessToCandidateContact(candidateId);
  }

  Future<PurchaseTransaction> purchaseCreditPack(CreditPack pack) async {
    final product = PaymentProducts.creditPackages.firstWhere(
      (p) => p.id == pack.id,
      orElse: () => PaymentProduct(
        id: pack.id,
        title: pack.title,
        subtitle: pack.subtitle,
        cents: pack.cents,
      ),
    );
    return purchaseContactProduct(product);
  }

  Future<PurchaseTransaction> purchaseContactProduct(
    PaymentProduct product, {
    String entryPoint = 'unknown',
    String? candidateId,
    String? rawCvDocId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = (currentUser?.uid ?? '').trim();
    final guestDirectUnlockWithoutAuth =
        currentUser == null &&
        product.id == PaymentProducts.credit1.id &&
        (candidateId ?? '').trim().isNotEmpty &&
        app_mode.AppMode.currentMode != app_mode.AccountMode.business;
    final guestContactOneAllowed =
        (currentUser != null &&
            currentUser.isAnonymous &&
            uid.isNotEmpty &&
            product.id == PaymentProducts.credit1.id &&
            app_mode.AppMode.currentMode != app_mode.AccountMode.business) ||
        guestDirectUnlockWithoutAuth;
    final blockedNoUser =
        currentUser == null ||
        uid.isEmpty ||
        uid.toLowerCase().startsWith('guest_');
    final blockedAnonymousPack =
        currentUser != null &&
        currentUser.isAnonymous &&
        !guestContactOneAllowed;
    final blockedNoUserWithoutGuestBypass =
        blockedNoUser && !guestDirectUnlockWithoutAuth;
    if (blockedNoUserWithoutGuestBypass || blockedAnonymousPack) {
      if (blockedAnonymousPack) {
        RuntimeFlowLogger.mark('GUEST_CONTACT_CHECKOUT_BLOCKED', <String, Object?>{
          'reason': 'anonymous_contact_pack_requires_sign_in',
          'productId': product.id,
          'entryPoint': entryPoint,
        });
      }
      if (blockedNoUserWithoutGuestBypass) {
        RuntimeFlowLogger.mark('GUEST_CONTACT_CHECKOUT_BLOCKED', <String, Object?>{
          'reason': 'auth_missing_for_non_guest_flow',
          'productId': product.id,
          'entryPoint': entryPoint,
        });
      }
      _logDebug(
        '[PAYMENT] blocked contact purchase: auth not ready/stable entryPoint=$entryPoint candidateId=${candidateId ?? ''} uid=$uid anon=${currentUser?.isAnonymous ?? true}',
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message: 'auth_required',
      );
    }
    final pending = _purchaseInFlight;
    if (pending != null) return pending;

    _analytics.trackPurchaseStarted(
      entryPoint: entryPoint,
      packId: product.id,
      creditsBefore: _creditsBalance,
      candidateId: candidateId,
    );
    final future = _purchaseProductInternal(
      product,
      entryPoint: entryPoint,
      candidateId: candidateId,
      rawCvDocId: rawCvDocId,
    );
    _purchaseInFlight = future;
    _safeNotify();
    return future.whenComplete(() {
      _purchaseInFlight = null;
      _safeNotify();
    });
  }

  Future<PurchaseTransaction> _purchaseProductInternal(
    PaymentProduct product, {
    required String entryPoint,
    String? candidateId,
    String? rawCvDocId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final cleanCandidateId = (candidateId ?? '').trim();
    _logDebug(
      '[PAYMENT] contact checkout payload candidateId=$cleanCandidateId product=${product.id} entryPoint=$entryPoint',
    );
    if (product.id == PaymentProducts.credit1.id && cleanCandidateId.isEmpty) {
      _logDebug(
        '[PAYMENT] blocked contact_1: missing candidateId entryPoint=$entryPoint',
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message: 'candidate_id_required',
      );
    }

    final isBusiness =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final isGuestContactOne =
        product.id == PaymentProducts.credit1.id &&
        !isBusiness &&
        (currentUser == null || currentUser.isAnonymous);
    final checkoutOwnerType = isGuestContactOne
        ? 'guest'
        : (isBusiness ? 'company' : 'user');
    final checkoutOwnerId = isGuestContactOne
        ? _repository.getOrCreateGuestSessionId()
        : (isBusiness
              ? app_mode.AppMode.activeCompanyId.trim()
              : (currentUser?.uid.trim() ?? ''));
    if (checkoutOwnerId.isEmpty) {
      RuntimeFlowLogger.mark('CONTACT_UNLOCK_SCOPE_INVALID', <String, Object?>{
        'entryPoint': entryPoint,
        'candidateId': cleanCandidateId,
        'productId': product.id,
        'currentMode': app_mode.AppMode.currentMode.name,
        'error': 'owner_scope_missing',
      });
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message:
            'Выберите компанию в бизнес-профиле или переключитесь в личный профиль.',
      );
    }

    final before = _creditsBalance;
    RuntimeFlowLogger.mark('CONTACT_CHECKOUT_CREATE_START', <String, Object?>{
      'productId': product.id,
      'entryPoint': entryPoint,
      'candidateId': cleanCandidateId,
      'currentMode': app_mode.AppMode.currentMode.name,
      'ownerType': checkoutOwnerType,
      'ownerId': checkoutOwnerId,
      'buyerUserId': currentUser?.uid.trim() ?? '',
      'buyerCompanyId': isBusiness ? app_mode.AppMode.activeCompanyId.trim() : '',
      'activeCompanyId': app_mode.AppMode.activeCompanyId.trim(),
      'creditsBefore': before,
    });
    try {
      if (kDebugMode) {
        _logDebug(
          '[PAYMENT] openPaymentFlow contact product=${product.id} entryPoint=$entryPoint candidateId=${candidateId ?? ''} creditsBefore=$before',
        );
      }
      final targetIdForCheckout = cleanCandidateId.isEmpty
          ? null
          : cleanCandidateId;
      final targetTypeForCheckout = targetIdForCheckout == null
          ? null
          : 'candidate';
      final rawCvForStripe =
          (rawCvDocId ?? '').trim().isNotEmpty ? (rawCvDocId ?? '').trim() : null;
      final paymentResult = await _stripeSheet.startCheckout(
        productId: product.id,
        quantity: 1,
        ownerType: checkoutOwnerType,
        ownerId: checkoutOwnerId,
        targetId: targetIdForCheckout,
        targetType: targetTypeForCheckout,
        sourceScreen: entryPoint,
        returnMode: targetIdForCheckout == null
            ? 'credits_only'
            : 'direct_unlock',
        contactRawCvDocId: rawCvForStripe,
      );
      if (paymentResult.status == PaymentSheetFlowStatus.cancelled) {
        _logDebug('[PAYMENT] checkout cancelled product=${product.id}');
        _analytics.trackPurchaseFailed(
          entryPoint: entryPoint,
          packId: product.id,
          creditsBefore: before,
          creditsAfter: _creditsBalance,
          resultStatus: 'cancelled',
          candidateId: candidateId,
        );
        return PurchaseTransaction(
          productId: product.id,
          amountCents: product.cents,
          status: PurchaseStatus.cancelled,
          createdAt: DateTime.now(),
          message: paymentResult.message,
        );
      }
      if (paymentResult.status == PaymentSheetFlowStatus.failed) {
        _logDebug(
          '[PAYMENT] checkout failed product=${product.id} message=${paymentResult.message}',
        );
        RuntimeFlowLogger.mark(
          'CONTACT_CHECKOUT_CREATE_FAILED',
          <String, Object?>{
            'productId': product.id,
            'entryPoint': entryPoint,
            'candidateId': cleanCandidateId,
            'ownerType': checkoutOwnerType,
            'ownerId': checkoutOwnerId,
            'reason': 'sheet_failed',
            'message': paymentResult.message,
          },
        );
        throw StateError(
          paymentResult.message.isEmpty
              ? 'Payment failed'
              : paymentResult.message,
        );
      }
      _logDebug('[PAYMENT] checkout opened product=${product.id}');
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.pending,
        createdAt: DateTime.now(),
        message: 'checkout_redirected',
      );
    } catch (e) {
      RuntimeFlowLogger.mark(
        'CONTACT_CHECKOUT_CREATE_FAILED',
        <String, Object?>{
          'productId': product.id,
          'entryPoint': entryPoint,
          'candidateId': cleanCandidateId,
          'ownerType': checkoutOwnerType,
          'ownerId': checkoutOwnerId,
          'reason': 'exception',
          'message': e.toString(),
        },
      );
      _analytics.trackPurchaseFailed(
        entryPoint: entryPoint,
        packId: product.id,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        resultStatus: 'failed',
        candidateId: candidateId,
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message: e.toString(),
      );
    }
  }

  Future<CreditSpendTransaction> spendCreditForCandidate({
    required String candidateId,
  }) async {
    final id = candidateId.trim();
    if (id.isEmpty) {
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: _creditsBalance,
        creditsAfter: _creditsBalance,
        status: CreditSpendStatus.failed,
        createdAt: DateTime.now(),
        message: 'candidateId is empty',
      );
    }
    final inFlight = _spendInFlightByCandidate[id];
    if (inFlight != null) return inFlight;
    final future = _spendCreditForCandidateInternal(id);
    _spendInFlightByCandidate[id] = future;
    _safeNotify();
    return future.whenComplete(() {
      _spendInFlightByCandidate.remove(id);
      _safeNotify();
    });
  }

  Future<CreditSpendTransaction> _spendCreditForCandidateInternal(
    String candidateId,
  ) async {
    final before = _creditsBalance;
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final ownerId =
        isBiz ? app_mode.AppMode.activeCompanyId.trim() : uid;
    final resolvedForLog =
        resolveCandidateContactKey(
          candidateId: candidateId,
          candidateKey: candidateId,
          canonicalCandidateId: null,
        ).trim();
    final keyLog =
        resolvedForLog.isNotEmpty ? resolvedForLog : candidateId.trim();
    if (hasAccessToCandidateContact(candidateId)) {
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: before,
        status: CreditSpendStatus.alreadyOpened,
        createdAt: DateTime.now(),
      );
    }
    RuntimeFlowLogger.mark('CONTACT_UNLOCK_SPEND_START', <String, Object?>{
      'candidateId': candidateId.trim(),
      'canonicalCandidateId': keyLog,
      'resolvedKey': keyLog,
      'ownerType': isBiz ? 'company' : 'user',
      'ownerId': ownerId,
      'creditsBefore': before,
    });
    try {
      final consume = await _repository.consumeCredit(candidateId: candidateId);
      final canonical = resolveCandidateContactKey(
        candidateId: candidateId,
        candidateKey: consume.contact.candidateId,
        canonicalCandidateId: consume.contact.candidateId,
      ).trim();
      final key = canonical.isEmpty ? candidateId : canonical;
      final status = (consume.alreadyUnlocked || !consume.spent)
          ? CreditSpendStatus.alreadyOpened
          : CreditSpendStatus.success;
      final didSpendOneCredit = consume.spent && !consume.alreadyUnlocked;
      final localCreditsAfter = didSpendOneCredit
          ? consume.creditsLeft
          : before;
      _creditsBalance = localCreditsAfter;
      _wallet = EmployerWallet(
        uid: _wallet?.uid ?? _uidScope,
        balance: _creditsBalance,
        unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
        fetchedAt: DateTime.now(),
      );
      applyUnlockedIds(<String>{
        ..._serverUnlockedCandidateIds,
        candidateId,
        if (canonical.isNotEmpty) canonical,
      });
      final hydrated = stateForCandidateKey(key).copyWith(
        hasEntitlement: true,
        contact: consume.contact,
        clearError: true,
        isLoadingContact: false,
      );
      _stateByKey[key] = hydrated;
      final aliases = _canonicalToCandidates[key];
      if (aliases != null) {
        for (final cvId in aliases) {
          final p = _stateByKey[cvId] ?? CandidateContactAccessState.initial();
          _stateByKey[cvId] = p.copyWith(
            hasEntitlement: true,
            contact: consume.contact,
            clearError: true,
            isLoadingContact: false,
          );
        }
      }
      _safeNotify();
      if (status == CreditSpendStatus.success) {
        RuntimeFlowLogger.mark('CONTACT_UNLOCK_SPEND_OK', <String, Object?>{
          'candidateId': candidateId.trim(),
          'canonicalCandidateId': key,
          'resolvedKey': key,
          'ownerType': isBiz ? 'company' : 'user',
          'ownerId': ownerId,
          'creditsAfter': _creditsBalance,
          'status': status.name,
        });
      } else {
        RuntimeFlowLogger.mark('CONTACT_UNLOCK_SPEND_OK', <String, Object?>{
          'candidateId': candidateId.trim(),
          'canonicalCandidateId': key,
          'resolvedKey': key,
          'ownerType': isBiz ? 'company' : 'user',
          'ownerId': ownerId,
          'creditsAfter': _creditsBalance,
          'status': status.name,
          'note': 'already_opened_or_no_debit',
        });
      }
      RuntimeFlowLogger.mark(
        'CONTACT_UNLOCK_ENTITLEMENT_CONFIRMED',
        <String, Object?>{
          'ownerType': isBiz ? 'business' : 'personal',
          'ownerId': ownerId,
          'canonicalCandidateId': key,
          'unlockedCount': _serverUnlockedCandidateIds.length,
          'contactLoaded': consume.contact.name.isNotEmpty ||
              consume.contact.email.isNotEmpty ||
              consume.contact.phone.isNotEmpty,
        },
      );
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        status: status,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      final msg = e.toString();
      final spendStatus = _isInsufficientCredits(msg)
          ? CreditSpendStatus.insufficientCredits
          : CreditSpendStatus.failed;
      RuntimeFlowLogger.mark('CONTACT_UNLOCK_SPEND_FAILED', <String, Object?>{
        'candidateId': candidateId.trim(),
        'canonicalCandidateId': keyLog,
        'resolvedKey': keyLog,
        'ownerType': isBiz ? 'company' : 'user',
        'ownerId': ownerId,
        'status': spendStatus.name,
        'message': msg,
      });
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        status: spendStatus,
        createdAt: DateTime.now(),
        message: msg,
      );
    }
  }

  Future<ContactUnlockResult> unlockCandidateContact(
    BuildContext context, {
    required String candidateId,
    required ContactUnlockSource source,
    String? candidateName,
    String entryPoint = 'unknown',
    String? uiCandidateId,
    String? candidateUid,
  }) async {
    return ensureContactUnlocked(
      context,
      candidateId: candidateId,
      source: source,
      candidateName: candidateName,
      entryPoint: entryPoint,
      uiCandidateId: uiCandidateId,
      candidateUid: candidateUid,
    );
  }

  Future<ContactUnlockResult> ensureContactUnlocked(
    BuildContext context, {
    required String candidateId,
    required ContactUnlockSource source,
    String? candidateName,
    String entryPoint = 'unknown',
    String? uiCandidateId,
    String? candidateUid,
  }) async {
    final id = candidateId.trim();
    if (id.isEmpty) {
      return const ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: 'candidateId is empty',
      );
    }

    final pending = _inFlightByCandidate[id];
    if (pending != null) return pending;

    _logDebug(
      '[CONTACT_UNLOCK] ensure start candidateId=$id entryPoint=$entryPoint '
      'ctrlHash=${identityHashCode(this)}',
    );
    RuntimeFlowLogger.mark('CONTACT_UNLOCK_TAP', <String, Object?>{
      'source': source.name,
      'candidateId': uiCandidateId ?? id,
      'canonicalId': id,
      'entryPoint': entryPoint,
    });
    lastAttemptedCandidateId = id;

    _analytics.trackContactUnlockTap(
      entryPoint: entryPoint,
      candidateId: id,
      creditsBefore: _creditsBalance,
    );

    await bootstrap(uid: FirebaseAuth.instance.currentUser?.uid);
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    final hasAccess = hasAccessToCandidateContact(id);
    _logDebug(
      '[UNLOCK_DECISION] candidateId=$id hasAccess=$hasAccess credits=$_creditsBalance',
    );
    if (hasAccess) {
      final cachedContact =
          stateForCandidateKey(id).contact ??
          await ensureLoadedContactForCandidate(id);
      if (context.mounted) {
        _showUnlockFeedback(
          context,
          message: 'Контакт уже открыт',
          success: false,
        );
      }
      _analytics.trackContactAlreadyUnlocked(
        entryPoint: entryPoint,
        candidateId: id,
        creditsBefore: _creditsBalance,
      );
      return ContactUnlockResult(
        status: ContactUnlockStatus.alreadyUnlocked,
        contact: cachedContact,
        creditsLeft: _creditsBalance,
        stabilizationStage: 'already_unlocked',
      );
    }

    final future = _unlockInternal(
      context,
      candidateId: id,
      source: source,
      candidateName: candidateName,
      entryPoint: entryPoint,
      uiCandidateId: uiCandidateId,
      candidateUid: candidateUid,
    ).then((result) async {
      // Wallet credit unlock already ran refreshUnlocked + ensureLoaded inside
      // [_unlockInternal]; avoid a second sweep that can stall UI while the
      // sheet waits on overlapping futures / transient bootstrap gates.
      if (result.stabilizationStage == 'unlock_via_wallet_credit') {
        RuntimeFlowLogger.mark(
          'CONTACT_CREDIT_UNLOCK_FLOW_DONE',
          <String, Object?>{
            'candidateId': uiCandidateId ?? id,
            'canonicalId': id,
            'creditsLeft': result.creditsLeft,
          },
        );
        _safeNotify();
        return result;
      }
      try {
        _logDebug('[CONTACT_UNLOCK] refresh unlocked ids candidateId=$id');
        await refreshUnlocked(force: true);
        await fetchContactForCandidate(id);
        _logDebug(
          '[CONTACT_UNLOCK] contact fetch completed candidateId=$id',
        );
      } catch (e) {
        _logDebug('[CONTACT_UNLOCK] post-purchase refresh failed $e');
      }
      _safeNotify();
      return result;
    });
    lastAttemptedCandidateId = id;
    _inFlightByCandidate[id] = future;
    try {
      return await future;
    } finally {
      _inFlightByCandidate.remove(id);
    }
  }

  Future<ContactUnlockResult> consumeCreditAndUnlockCandidate({
    required String canonicalCandidateId,
    String entryPoint = 'unknown',
    String? rawCandidateId,
    String? cvId,
  }) async {
    final canonical = canonicalCandidateId.trim();
    if (canonical.isEmpty) {
      return const ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: 'candidate_id_unresolved',
      );
    }
    await bootstrap(uid: FirebaseAuth.instance.currentUser?.uid);
    final isBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final ownerType = isBiz ? 'business' : 'personal';
    final ownerId = isBiz ? app_mode.AppMode.activeCompanyId.trim() : uid;
    if (ownerId.isEmpty) {
      return const ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: 'owner_scope_missing',
      );
    }

    RuntimeFlowLogger.mark('CONTACT_CREDIT_CONSUME_START', <String, Object?>{
      'ownerType': ownerType,
      'ownerId': ownerId,
      'candidateId': (rawCandidateId ?? '').trim(),
      'canonicalCandidateId': canonical,
      'cvId': (cvId ?? '').trim(),
      'credits': _creditsBalance,
      'entryPoint': entryPoint,
    });

    final spendTx = await spendCreditForCandidate(candidateId: canonical);
    if (spendTx.status != CreditSpendStatus.success &&
        spendTx.status != CreditSpendStatus.alreadyOpened) {
      return ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: spendTx.message.isNotEmpty
            ? spendTx.message
            : 'credit_consume_failed',
        creditsLeft: _creditsBalance,
      );
    }

    await refreshUnlocked(force: true);
    CandidateContact? contact;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        contact = await ensureLoadedContactForCandidate(canonical);
      } catch (_) {}
      if (contact != null) break;
      await Future<void>.delayed(Duration(milliseconds: 110 * (attempt + 1)));
    }
    final hasAccess = hasAccessToCandidateContact(canonical);
    final contactLoaded = contact != null;
    RuntimeFlowLogger.mark('CONTACT_CREDIT_CONSUME_OK', <String, Object?>{
      'ownerType': ownerType,
      'ownerId': ownerId,
      'canonicalCandidateId': canonical,
      'rawCandidateId': (rawCandidateId ?? '').trim(),
      'cvId': (cvId ?? '').trim(),
      'credits': _creditsBalance,
      'unlockedCount': _serverUnlockedCandidateIds.length,
      'hasAccess': hasAccess,
      'contactLoaded': contactLoaded,
      'entryPoint': entryPoint,
    });
    RuntimeFlowLogger.mark('CONTACT_UNLOCK_ENTITLEMENT_CONFIRMED', <String, Object?>{
      'ownerType': ownerType,
      'ownerId': ownerId,
      'canonicalCandidateId': canonical,
      'unlockedCount': _serverUnlockedCandidateIds.length,
      'contactLoaded': contactLoaded,
    });
    final unlockedOk = hasAccess && contactLoaded;
    return ContactUnlockResult(
      status: unlockedOk ? ContactUnlockStatus.unlocked : ContactUnlockStatus.failed,
      contact: contact,
      creditsLeft: _creditsBalance,
      stabilizationStage: unlockedOk
          ? 'unlock_via_direct_credit_consume'
          : 'unlock_via_direct_credit_consume_failed',
      message: unlockedOk ? '' : 'contact_payload_or_entitlement_missing',
    );
  }

  Future<ContactUnlockResult> _unlockInternal(
    BuildContext context, {
    required String candidateId,
    required ContactUnlockSource source,
    String? candidateName,
    required String entryPoint,
    String? uiCandidateId,
    String? candidateUid,
  }) async {
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    try {
      await _refreshAuthoritativeCreditsState(reason: 'pre_unlock_attempt');
    } catch (_) {}
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    final enteredCreditsBranch = _creditsBalance > 0;
    if (enteredCreditsBranch) {
      RuntimeFlowLogger.mark(
        'CONTACT_CREDIT_UNLOCK_FLOW_START',
        <String, Object?>{
          'candidateId': uiCandidateId ?? candidateId,
          'canonicalId': candidateId,
          'entryPoint': entryPoint,
          'credits': _creditsBalance,
        },
      );
      final creditsBeforeConfirm = _creditsBalance;
      final approved = await _confirmCreditSpend(
        context,
        creditsBefore: creditsBeforeConfirm,
      );
      if (!approved) {
        return const ContactUnlockResult(
          status: ContactUnlockStatus.cancelled,
          message: 'Открытие отменено',
          stabilizationStage: 'unlock_cancelled_before_spend',
        );
      }
      try {
        await _refreshAuthoritativeCreditsState(
          reason: 'pre_credit_spend_confirmation',
        );
      } catch (_) {}
      if (_creditsBalance <= 0) {
        return ContactUnlockResult(
          status: ContactUnlockStatus.failed,
          message:
              'Баланс обновился: контактов не осталось. Попробуйте снова, чтобы открыть покупку.',
          creditsLeft: _creditsBalance,
          stabilizationStage: 'unlock_balance_changed_before_spend',
        );
      }
      _logDebug(
        '[CREDIT_CONSUME_START] candidateId=$candidateId creditsBefore=$_creditsBalance',
      );
      final spendTx = await spendCreditForCandidate(candidateId: candidateId);
      final spendUnlocked =
          spendTx.status == CreditSpendStatus.success ||
          spendTx.status == CreditSpendStatus.alreadyOpened;
      _logDebug(
        '[CREDIT_CONSUME_DONE] candidateId=$candidateId status=${spendTx.status.name} creditsLeft=${spendTx.creditsAfter} unlocked=$spendUnlocked',
      );
      if (spendTx.status == CreditSpendStatus.success ||
          spendTx.status == CreditSpendStatus.alreadyOpened) {
        RuntimeFlowLogger.mark(
          'CONTACT_CREDIT_UNLOCK_FLOW_SPEND_OK',
          <String, Object?>{
            'candidateId': uiCandidateId ?? candidateId,
            'canonicalId': candidateId,
            'status': spendTx.status.name,
            'creditsAfter': spendTx.creditsAfter,
          },
        );
        await refreshUnlocked(force: true);
        CandidateContact? contact;
        RuntimeFlowLogger.mark(
          'CONTACT_CREDIT_UNLOCK_FLOW_LOAD_START',
          <String, Object?>{
            'candidateId': uiCandidateId ?? candidateId,
            'canonicalId': candidateId,
          },
        );
        for (var attempt = 0; attempt < 5; attempt++) {
          try {
            contact = await ensureLoadedContactForCandidate(candidateId);
          } catch (e) {
            RuntimeFlowLogger.mark(
              'CONTACT_CREDIT_UNLOCK_FLOW_LOAD_FAILED',
              <String, Object?>{
                'candidateId': uiCandidateId ?? candidateId,
                'canonicalId': candidateId,
                'error': e.toString(),
                'attempt': attempt,
              },
            );
          }
          if (contact != null) break;
          await Future<void>.delayed(Duration(milliseconds: 110 * (attempt + 1)));
        }
        if (contact != null) {
          RuntimeFlowLogger.mark(
            'CONTACT_CREDIT_UNLOCK_FLOW_LOAD_OK',
            <String, Object?>{
              'candidateId': uiCandidateId ?? candidateId,
              'canonicalId': candidateId,
              'hasContact': true,
            },
          );
        } else {
          RuntimeFlowLogger.mark(
            'CONTACT_CREDIT_UNLOCK_FLOW_LOAD_FAILED',
            <String, Object?>{
              'candidateId': uiCandidateId ?? candidateId,
              'canonicalId': candidateId,
              'error': 'contact_payload_missing_after_retries',
            },
          );
        }
        if (contact != null) {
          _analytics.trackContactUnlockSuccess(
            entryPoint: entryPoint,
            candidateId: candidateId,
            creditsBefore: spendTx.creditsBefore,
            creditsAfter: spendTx.creditsAfter,
          );
        }
        if (context.mounted) {
          if (spendTx.status == CreditSpendStatus.success) {
            _showUnlockFeedback(
              context,
              message:
                  '1 кредит списан. Остаток баланса: ${spendTx.creditsAfter}',
            );
          } else {
            _showUnlockFeedback(
              context,
              message: 'Контакт уже открыт',
              success: false,
            );
          }
        }
        final walletUnlocked = contact != null;
        return ContactUnlockResult(
          status: walletUnlocked
              ? ContactUnlockStatus.unlocked
              : ContactUnlockStatus.failed,
          contact: contact,
          creditsLeft: _creditsBalance,
          stabilizationStage: walletUnlocked
              ? 'unlock_via_wallet_credit'
              : 'unlock_via_wallet_credit_payload_missing',
          message: walletUnlocked ? '' : 'contact_payload_missing',
        );
      }
      if (spendTx.status == CreditSpendStatus.failed) {
        return ContactUnlockResult(
          status: ContactUnlockStatus.failed,
          message: spendTx.message.isNotEmpty
              ? spendTx.message
              : 'Не удалось списать контакт с баланса',
          creditsLeft: _creditsBalance,
          stabilizationStage: 'unlock_via_wallet_credit_failed',
        );
      }
      if (spendTx.status == CreditSpendStatus.insufficientCredits) {
        try {
          await _refreshAuthoritativeCreditsState(
            reason: 'post_unlock_insufficient_credits_refresh',
          );
        } catch (_) {}
        return ContactUnlockResult(
          status: ContactUnlockStatus.failed,
          message: 'Недостаточно контактов для открытия кандидата',
          creditsLeft: _creditsBalance,
          stabilizationStage: 'unlock_via_wallet_credit_insufficient',
        );
      }
      try {
        await _refreshAuthoritativeCreditsState(
          reason: 'post_unlock_credit_branch_refresh',
        );
      } catch (_) {}
      return ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: spendTx.message.isNotEmpty
            ? spendTx.message
            : 'Не удалось завершить открытие контакта',
        creditsLeft: _creditsBalance,
        stabilizationStage: 'unlock_via_wallet_credit_unresolved',
      );
    }

    _logDebug(
      '[UNLOCK_DECISION_PAYWALL] candidateId=$candidateId credits=$_creditsBalance hasAccess=${hasAccessToCandidateContact(candidateId)}',
    );
    RuntimeFlowLogger.mark('MONETIZATION_ENTRYPOINT_TAP', <String, Object?>{
      'flow': 'contact_unlock_paywall',
      'source': source.name,
      'candidateId': (uiCandidateId ?? '').trim(),
      'canonicalId': candidateId,
      'entryPoint': entryPoint,
    });
    RuntimeFlowLogger.mark('PAYWALL_OPEN_ATTEMPT', <String, Object?>{
      'source': source.name,
      'candidateId': (uiCandidateId ?? '').trim(),
      'canonicalId': candidateId,
      'entryPoint': entryPoint,
    });
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (kIsWeb && currentUid.isNotEmpty) {
      setPendingUnlockIntentForUid(currentUid, candidateId);
    }
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    final isGuestNow = _isGuestSurface();
    RuntimeFlowLogger.mark('CONTACT_UNLOCK_PAYWALL_CALL', <String, Object?>{
      'source': source.name,
      'candidateId': (uiCandidateId ?? '').trim(),
      'canonicalCandidateId': candidateId,
      'buyerSig': _computeBuyerScopeSig(),
      'isGuest': isGuestNow,
      'credits': _creditsBalance,
      'entryPoint': entryPoint,
      'enteredCreditsBranch': enteredCreditsBranch,
    });

    final paywallResult = await ContactUnlockPaywallSheet.open(
      context,
      candidateName: candidateName,
      candidateId: (uiCandidateId ?? '').trim().isEmpty
          ? null
          : uiCandidateId!.trim(),
      candidateUid: (candidateUid ?? '').trim().isNotEmpty
          ? candidateUid!.trim()
          : null,
      canonicalCandidateId: candidateId,
      entryPoint: entryPoint,
      mode: PaywallMode.directUnlock,
      originContext: ContactUnlockOriginContext(
        source: source,
        candidateId: (uiCandidateId ?? '').trim().isNotEmpty
            ? uiCandidateId!.trim()
            : candidateId,
        candidateUid: (candidateUid ?? '').trim().isNotEmpty
            ? candidateUid!.trim()
            : null,
        canonicalId: candidateId,
        resolvedKey: candidateId,
      ),
    );
    final outcome = paywallResult.outcome;
    switch (outcome) {
      case ContactUnlockPaywallOutcome.alreadyUnlocked:
        await refreshUnlocked(force: true);
        CandidateContact? contact;
        try {
          contact = await ensureLoadedContactForCandidate(candidateId);
        } catch (_) {}
        final hasAccess = hasAccessToCandidateContact(candidateId);
        final contactLoaded = contact != null;
        final unlocked = hasAccess && contactLoaded;
        final result = ContactUnlockResult(
          status: unlocked
              ? ContactUnlockStatus.unlocked
              : ContactUnlockStatus.failed,
          contact: contact,
          creditsLeft: _creditsBalance,
          stabilizationStage: unlocked
              ? 'unlock_already_unlocked_payload_ready'
              : 'unlock_already_unlocked_payload_missing',
          message: unlocked ? '' : 'contact_payload_or_entitlement_missing',
        );
        RuntimeFlowLogger.mark(
          'CONTACT_UNLOCK_ORCHESTRATION_DECISION',
          <String, Object?>{
            'outcome': outcome.name,
            'action': 'refresh_and_ensure_payload',
            'hasAccess': hasAccess,
            'contactLoaded': contactLoaded,
            'returnedStatus': result.status.name,
          },
        );
        return result;
      case ContactUnlockPaywallOutcome.directUnlockSucceeded:
        await refreshUnlocked(force: true);
        CandidateContact? contact;
        try {
          contact = await ensureLoadedContactForCandidate(candidateId);
        } catch (_) {}
        final hasAccess = hasAccessToCandidateContact(candidateId);
        final contactLoaded = contact != null;
        final unlocked = hasAccess && contactLoaded;
        final result = ContactUnlockResult(
          status: unlocked
              ? ContactUnlockStatus.unlocked
              : ContactUnlockStatus.failed,
          contact: contact,
          creditsLeft: _creditsBalance,
          stabilizationStage: unlocked
              ? 'unlock_direct_success_payload_ready'
              : 'unlock_direct_success_payload_missing',
          message: unlocked ? '' : 'contact_payload_or_entitlement_missing',
        );
        RuntimeFlowLogger.mark(
          'CONTACT_UNLOCK_ORCHESTRATION_DECISION',
          <String, Object?>{
            'outcome': outcome.name,
            'action': 'refresh_force_and_ensure_payload',
            'hasAccess': hasAccess,
            'contactLoaded': contactLoaded,
            'returnedStatus': result.status.name,
          },
        );
        return result;
      case ContactUnlockPaywallOutcome.checkoutStarted:
        final pendingResult = ContactUnlockResult(
          status: ContactUnlockStatus.purchasePending,
          message: 'Ожидаем подтверждение оплаты. Контакт откроется автоматически.',
          creditsLeft: _creditsBalance,
          stabilizationStage: 'unlock_pending_after_checkout_redirect',
          recentPurchase: true,
        );
        RuntimeFlowLogger.mark(
          'CONTACT_UNLOCK_ORCHESTRATION_DECISION',
          <String, Object?>{
            'outcome': outcome.name,
            'action': 'await_payment_restore',
            'hasAccess': hasAccessToCandidateContact(candidateId),
            'contactLoaded': contactForCandidate(candidateId) != null,
            'returnedStatus': pendingResult.status.name,
          },
        );
        return pendingResult;
      case ContactUnlockPaywallOutcome.cancelled:
        _analytics.trackContactUnlockFailed(
          entryPoint: entryPoint,
          candidateId: candidateId,
          creditsBefore: _creditsBalance,
          creditsAfter: _creditsBalance,
          resultStatus: 'cancelled',
        );
        RuntimeFlowLogger.mark(
          'CONTACT_UNLOCK_ORCHESTRATION_DECISION',
          <String, Object?>{
            'outcome': outcome.name,
            'action': 'cancel_unlock',
            'hasAccess': hasAccessToCandidateContact(candidateId),
            'contactLoaded': contactForCandidate(candidateId) != null,
            'returnedStatus': ContactUnlockStatus.cancelled.name,
          },
        );
        return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
      case ContactUnlockPaywallOutcome.failed:
        _analytics.trackContactUnlockFailed(
          entryPoint: entryPoint,
          candidateId: candidateId,
          creditsBefore: _creditsBalance,
          creditsAfter: _creditsBalance,
          resultStatus: 'failed',
        );
        RuntimeFlowLogger.mark(
          'CONTACT_UNLOCK_ORCHESTRATION_DECISION',
          <String, Object?>{
            'outcome': outcome.name,
            'action': 'fail_unlock',
            'hasAccess': hasAccessToCandidateContact(candidateId),
            'contactLoaded': contactForCandidate(candidateId) != null,
            'returnedStatus': ContactUnlockStatus.failed.name,
          },
        );
        return ContactUnlockResult(
          status: ContactUnlockStatus.failed,
          message: paywallResult.reason ?? 'paywall_failed',
          creditsLeft: _creditsBalance,
          stabilizationStage: 'unlock_paywall_failed',
        );
    }
  }

  static bool _isInsufficientCredits(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('insufficient') ||
        lower.contains('недостат') ||
        lower.contains('credits');
  }

  Future<void> _applyAuthoritativeWalletState(
    EmployerWallet wallet, {
    String? uid,
  }) async {
    applyUnlockedIds(wallet.unlockedCandidateIds);
    _walletRefreshError = null;
    _creditsBalance = wallet.balance;
    _wallet = EmployerWallet(
      uid: wallet.uid,
      balance: wallet.balance,
      unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
      fetchedAt: wallet.fetchedAt,
    );
    await _unlockStore.replaceOpenedIds(
      _serverUnlockedCandidateIds,
      uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
    );
    _safeNotify();
  }

  Future<EmployerWallet> _refreshAuthoritativeCreditsState({
    required String reason,
  }) async {
    if (_isGuestSurface()) {
      _walletRefreshError = null;
      _creditsBalance = 0;
      final fallback = EmployerWallet(
        uid: 'guest',
        balance: 0,
        unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
        fetchedAt: DateTime.now(),
      );
      _wallet = fallback;
      if (kDebugMode) {
        _logDebug(
          '[ContactAccessController] authoritative credits refresh skipped reason=$reason guest_surface=true',
        );
      }
      return fallback;
    }
    final wallet = await _repository.getAuthoritativeEmployerWalletState();
    await _applyAuthoritativeWalletState(
      wallet,
      uid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (kDebugMode) {
      _logDebug(
        '[ContactAccessController] authoritative credits refresh reason=$reason balance=${wallet.balance} unlocked=${wallet.unlockedCandidateIds.length}',
      );
    }
    return wallet;
  }

  Future<ContactRestoreDisposition> restoreAfterPaywallExit(
    BuildContext context, {
    bool purchased = false,
    Future<void> Function(
      String candidateId,
      String? canonicalId,
      String candidateUid,
    )?
    onExpandedRestore,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final isGuest =
        uid.isEmpty || (user?.isAnonymous ?? false) || uid == 'guest';
    final guestScopeId = _repository.peekGuestSessionId().trim();
    RuntimeFlowLogger.mark('GUEST_CONTACT_RETURN_RESTORE', <String, Object?>{
      'uid': uid,
      'guestSessionId': guestScopeId,
      'isGuest': isGuest,
      'purchased': purchased,
    });
    if (isGuest && guestScopeId.isEmpty) {
      RuntimeFlowLogger.mark(
        'CONTACT_RESTORE_GUEST_SESSION_MISSING',
        <String, Object?>{
          'phase': 'restore_after_paywall_exit',
          'purchased': purchased,
        },
      );
      navTrace('CONTACT_RESTORE_END', {
        'candidateId': '',
        'visibleUiContext': 'blocked_missing_guest_session',
      });
      clearPendingOrigin(reason: 'restore_guest_session_missing');
      return ContactRestoreDisposition.noOrigin;
    }
    await bootstrapForBuyerScope(source: 'restore_after_paywall_exit');
    if (!isGuest && uid != _uidScope) {
      _logDebug(
        '[CONTACT_RESTORE_SKIPPED] reason=auth_scope_mismatch currentScope=$_uidScope activeUid=$uid',
      );
      return ContactRestoreDisposition.noOrigin;
    }

    var origin = _pendingOriginContext;
    origin ??= _loadPendingOriginFromStorage();
    if (origin == null) {
      navTrace('CONTACT_RESTORE_END', {
        'candidateId': '',
        'visibleUiContext': 'none',
      });
      clearPendingOrigin(reason: 'restore_missing_origin');
      return ContactRestoreDisposition.noOrigin;
    }
    final restoredOrigin = origin;
    final resolveCandidateId = restoredOrigin.candidateId;
    final resolveCandidateUid =
        (restoredOrigin.candidateUid ?? '').trim().isNotEmpty
        ? (restoredOrigin.candidateUid ?? '').trim()
        : resolveCandidateId;
    final restoreKey = resolveCandidateContactKey(
      candidateId: restoredOrigin.candidateId,
      candidateKey: restoredOrigin.resolvedKey ?? restoredOrigin.candidateId,
      canonicalCandidateId: restoredOrigin.canonicalId,
    );
    final rkTrim = restoreKey.trim();
    final cvTrim = resolveCandidateId.trim();
    if (rkTrim.isNotEmpty && cvTrim.isNotEmpty) {
      registerCanonicalMapping(
        canonicalCandidateId: rkTrim,
        candidateId: cvTrim,
      );
    }
    beginPaymentRestoreSignal(
      restoreKey: restoreKey,
      candidateId: resolveCandidateId,
    );
    try {
      RuntimeFlowLogger.mark('CONTACT_ACCESS_KEY_RESOLVE', <String, Object?>{
      'source': 'contact_access_controller.restoreAfterPaywallExit',
      'rawCandidateId': restoredOrigin.candidateId,
      'canonicalCandidateId': restoredOrigin.canonicalId ?? '',
      'cvId': restoredOrigin.candidateId,
      'candidateOwnerId': resolveCandidateUid,
      'resolvedContactKey': restoreKey,
      'isCanonicalUuid': restoreKey.isNotEmpty,
    });
    navTrace('CONTACT_RESTORE_BEGIN', {
      'sourceType': origin.source.name,
      'candidateId': resolveCandidateId,
      'canonicalId': restoredOrigin.canonicalId ?? '',
      'purchased': purchased ? 'true' : 'false',
    });
    final restoreIsBiz =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final restoreUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final restoreOwnerType = restoreIsBiz
        ? 'company'
        : ((restoreUid.isEmpty || (FirebaseAuth.instance.currentUser?.isAnonymous ?? false))
              ? 'guest'
              : 'user');
    final restoreOwnerId = restoreIsBiz
        ? app_mode.AppMode.activeCompanyId.trim()
        : (restoreOwnerType == 'guest' ? guestScopeId : restoreUid);
    RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CONSUME', <String, Object?>{
      'source': restoredOrigin.source.name,
      'candidateId': resolveCandidateId,
      'canonicalCandidateId': restoredOrigin.canonicalId ?? '',
      'resolvedKey': restoreKey,
      'purchased': purchased,
      'mode': app_mode.AppMode.currentMode.name,
      'ownerType': restoreOwnerType,
      'ownerId': restoreOwnerId,
    });
    _logDebug('[RESTORE_FLOW_START] candidateId=$resolveCandidateId');
    _logDebug('[RESTORE_FLOW_RESOLVED_KEY] resolvedKey=$restoreKey');
    _logDebug('[RESTORE_FLOW_REFRESH_UNLOCKED_START]');
    await refreshUnlocked(force: true);
    var hasAccess =
        restoreKey.isNotEmpty && hasAccessToCandidateContact(restoreKey);
    _logDebug('[RESTORE_FLOW_REFRESH_UNLOCKED_DONE] hasAccess=$hasAccess');

    // If purchased and unlock not yet visible (webhook lag), poll a few times.
    if (purchased && restoreKey.isNotEmpty && !hasAccess) {
      const attempts = 15;
      const delay = Duration(milliseconds: 500);
      for (var i = 0; i < attempts; i++) {
        await Future<void>.delayed(delay);
        await refreshUnlocked(force: true);
        hasAccess = hasAccessToCandidateContact(restoreKey);
        RuntimeFlowLogger.mark('CONTACT_RESTORE_ACCESS_POLL', <String, Object?>{
          'attempt': i + 1,
          'maxAttempts': attempts,
          'resolvedKey': restoreKey,
          'hasAccess': hasAccess,
          'purchased': purchased,
        });
        _logDebug(
          '[RESTORE_FLOW_REFRESH_UNLOCKED_RETRY] attempt=${i + 1}/$attempts hasAccess=$hasAccess',
        );
        if (hasAccess) break;
      }
    }

    final accessVisible =
        restoreKey.isNotEmpty && hasAccessToCandidateContact(restoreKey);
    final contactVisible =
        restoreKey.isNotEmpty && contactForCandidate(restoreKey) != null;
    RuntimeFlowLogger.mark('GUEST_CONTACT_ACCESS_RESULT', <String, Object?>{
      'hasAccess': accessVisible,
      'hasContact': contactVisible,
      'resolvedKey': restoreKey,
      'isGuest': isGuest,
      'purchased': purchased,
    });
    if (accessVisible) {
      RuntimeFlowLogger.mark('GUEST_CONTACT_UNLOCK_VISIBLE', <String, Object?>{
        'hasAccess': true,
        'hasContact': contactVisible,
        'resolvedKey': restoreKey,
        'isGuest': isGuest,
      });
    }
    _logDebug(
      '[RESTORE_FLOW_ACCESS_VISIBLE] '
      'key=$restoreKey hasAccess=$accessVisible hasContact=$contactVisible',
    );
    if (resolveCandidateId.trim().isEmpty && restoreKey.isEmpty) {
      navTrace('CONTACT_RESTORE_SKIP', {
        'sourceType': origin.source.name,
        'reason': 'empty_candidate_id',
      });
      clearPendingOrigin(reason: 'missing_candidate_id_restore');
      return ContactRestoreDisposition.noOrigin;
    }
    final isExpandedOrigin =
        restoredOrigin.source == ContactUnlockSource.expandedCandidateCard;
    final canExpandedCandidateDetails =
        onExpandedRestore != null &&
        resolveCandidateUid.trim().isNotEmpty;

    final originCanon = (restoredOrigin.canonicalId ?? '').trim();
    final rkForCanon = restoreKey.trim();
    final cvIdForCanon = resolveCandidateId.trim();
    final String? canonicalForSheet =
        CandidateIdentityResolver.isUuid(originCanon)
        ? originCanon
        : (CandidateIdentityResolver.isUuid(rkForCanon) ? rkForCanon : null);

    if (canExpandedCandidateDetails && purchased) {
      if (!accessVisible) {
        RuntimeFlowLogger.mark(
          'CONTACT_RESTORE_REOPEN_SKIPPED',
          <String, Object?>{
            'reason': 'no_backend_contact_access',
            'candidateId': resolveCandidateId,
            'resolvedKey': restoreKey,
            'purchased': true,
            'source': restoredOrigin.source.name,
          },
        );
        navTrace('CONTACT_RESTORE_END', {
          'candidateId': resolveCandidateId,
          'visibleUiContext': 'blocked_no_entitlement_payment_restore',
        });
        clearPendingOrigin(reason: 'restore_payment_blocked_no_backend_access');
        return ContactRestoreDisposition.noOrigin;
      }
      final reopenGuard = restoreKey.isNotEmpty
          ? restoreKey
          : CandidateDetailsRouteCoordinator.buildDetailsGuardKey(
              candidateId: resolveCandidateId,
              candidateUid: resolveCandidateUid,
              canonicalCandidateId: restoredOrigin.canonicalId,
            );
      final buyerSigRestore = computeBuyerScopeSig(silent: true);
      RuntimeFlowLogger.mark('CONTACT_RESTORE_REOPEN_START', <String, Object?>{
        'candidateId': resolveCandidateId,
        'resolvedKey': reopenGuard,
        'source': restoredOrigin.source.name,
        'purchased': true,
        'hasAccess': true,
      });
      if (reopenGuard.isNotEmpty &&
          isPaymentRestoreReopenConsumedForKey(reopenGuard)) {
        RuntimeFlowLogger.mark(
          'CONTACT_RESTORE_REOPEN_SKIPPED',
          <String, Object?>{
            'reason': 'already_consumed',
            'candidateId': resolveCandidateId,
            'resolvedKey': reopenGuard,
          },
        );
        clearPendingOrigin(reason: 'restore_reopen_already_consumed');
        RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CLEARED', <String, Object?>{
          'reason': 'already_consumed',
          'resolvedKey': reopenGuard,
          'candidateId': resolveCandidateId,
        });
        return ContactRestoreDisposition.expandedDetailsRestored;
      }
      String reopenSkipReason = '';
      if (CandidateDetailsRouteCoordinator.isDetailsGuardKeyActive(reopenGuard)) {
        reopenSkipReason = 'already_open';
      } else if (CandidateDetailsRouteCoordinator.isDetailsGuardKeyOpeningInFlight(
            reopenGuard,
          )) {
        reopenSkipReason = 'in_flight';
      }
      if (reopenSkipReason.isNotEmpty) {
        RuntimeFlowLogger.mark(
          'CONTACT_RESTORE_REOPEN_SKIPPED',
          <String, Object?>{
            'reason': reopenSkipReason,
            'candidateId': resolveCandidateId,
            'resolvedKey': reopenGuard,
          },
        );
        clearPendingOrigin(reason: 'restore_reopen_sheet_already_visible');
        RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CLEARED', <String, Object?>{
          'reason': 'opened_once',
          'resolvedKey': reopenGuard,
          'candidateId': resolveCandidateId,
        });
        return ContactRestoreDisposition.expandedDetailsRestored;
      }
      _logDebug(
        '[RESTORE_FLOW_REOPEN] '
        'candidateId=$resolveCandidateId canonical=$restoreKey '
        'hasAccess=$accessVisible hasContact=$contactVisible',
      );
      final canonOpen = (canonicalForSheet ?? '').trim();
      if (!CandidateIdentityResolver.isUuid(canonOpen)) {
        RuntimeFlowLogger.mark(
          'CONTACT_RESTORE_PURCHASED_CANONICAL_MISSING',
          <String, Object?>{
            'resolvedKey': reopenGuard,
            'rawCvId': cvIdForCanon,
            'buyerSig': buyerSigRestore,
          },
        );
        navTrace('CONTACT_RESTORE_END', {
          'candidateId': resolveCandidateId,
          'visibleUiContext': 'blocked_missing_canonical',
        });
        clearPendingOrigin(reason: 'restore_canonical_missing');
        return ContactRestoreDisposition.noOrigin;
      }
      RuntimeFlowLogger.mark(
        'CONTACT_RESTORE_ACCESS_VERIFIED',
        <String, Object?>{
          'resolvedKey': reopenGuard,
          'rawCvId': cvIdForCanon,
          'canonicalCandidateId': canonOpen,
          'buyerSig': buyerSigRestore,
          'hasContact': contactVisible,
        },
      );
      RuntimeFlowLogger.mark(
        'CONTACT_REOPEN_CANDIDATE_DETAILS_START',
        <String, Object?>{
          'rawCvId': cvIdForCanon,
          'canonicalCandidateId': canonOpen,
          'resolvedKey': reopenGuard,
          'source': restoredOrigin.source.name,
          'purchased': true,
          'hasAccess': true,
          'hasContact': contactVisible,
          'buyerSig': buyerSigRestore,
        },
      );
      await onExpandedRestore(
        cvIdForCanon,
        canonicalForSheet,
        resolveCandidateUid,
      );
      RuntimeFlowLogger.mark('CONTACT_RESTORE_REOPEN_DONE', <String, Object?>{
        'candidateId': resolveCandidateId,
        'resolvedKey': reopenGuard,
      });
      RuntimeFlowLogger.mark(
        'CONTACT_REOPEN_CANDIDATE_DETAILS_OK',
        <String, Object?>{
          'rawCvId': cvIdForCanon,
          'canonicalCandidateId': canonOpen,
          'resolvedKey': reopenGuard,
          'source': restoredOrigin.source.name,
          'buyerSig': buyerSigRestore,
          'hasAccess': true,
          'purchased': true,
        },
      );
      if (reopenGuard.isNotEmpty) {
        markPaymentRestoreReopenConsumedKey(reopenGuard);
      }
      navTrace('CONTACT_RESTORE_ACTION', {
        'action': 'open_details_after_payment',
        'candidateId': resolveCandidateId,
      });
      navTrace('CONTACT_RESTORE_END', {
        'candidateId': resolveCandidateId,
        'visibleUiContext': 'candidate_details',
      });
      clearPendingOrigin(reason: 'restore_after_paywall_exit_complete');
      RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CLEARED', <String, Object?>{
        'reason': 'opened_once',
        'resolvedKey': reopenGuard,
        'candidateId': resolveCandidateId,
      });
      return ContactRestoreDisposition.expandedDetailsRestored;
    }

    if (canExpandedCandidateDetails &&
        !purchased &&
        isExpandedOrigin &&
        accessVisible) {
      final reopenGuard = restoreKey.isNotEmpty
          ? restoreKey
          : CandidateDetailsRouteCoordinator.buildDetailsGuardKey(
              candidateId: resolveCandidateId,
              candidateUid: resolveCandidateUid,
              canonicalCandidateId: restoredOrigin.canonicalId,
            );
      String reopenSkipReason = '';
      if (CandidateDetailsRouteCoordinator.isDetailsGuardKeyActive(reopenGuard)) {
        reopenSkipReason = 'already_open';
      } else if (CandidateDetailsRouteCoordinator.isDetailsGuardKeyOpeningInFlight(
            reopenGuard,
          )) {
        reopenSkipReason = 'in_flight';
      }
      if (reopenSkipReason.isNotEmpty) {
        RuntimeFlowLogger.mark(
          'CONTACT_OPEN_CANDIDATE_DETAILS_SKIPPED',
          <String, Object?>{
            'reason': reopenSkipReason,
            'candidateId': resolveCandidateId,
            'resolvedKey': reopenGuard,
          },
        );
        clearPendingOrigin(reason: 'restore_non_payment_sheet_already_visible');
        return ContactRestoreDisposition.expandedDetailsRestored;
      }
      final buyerSigOpen = computeBuyerScopeSig(silent: true);
      RuntimeFlowLogger.mark(
        'CONTACT_OPEN_CANDIDATE_DETAILS_START',
        <String, Object?>{
          'rawCvId': cvIdForCanon,
          'canonicalCandidateId': canonicalForSheet ?? '',
          'resolvedKey': reopenGuard,
          'source': restoredOrigin.source.name,
          'hasAccess': true,
          'hasContact': contactVisible,
          'buyerSig': buyerSigOpen,
        },
      );
      await onExpandedRestore(
        cvIdForCanon,
        canonicalForSheet,
        resolveCandidateUid,
      );
      RuntimeFlowLogger.mark(
        'CONTACT_OPEN_CANDIDATE_DETAILS_OK',
        <String, Object?>{
          'rawCvId': cvIdForCanon,
          'canonicalCandidateId': canonicalForSheet ?? '',
          'resolvedKey': reopenGuard,
          'source': restoredOrigin.source.name,
          'buyerSig': buyerSigOpen,
          'hasAccess': true,
        },
      );
      navTrace('CONTACT_RESTORE_ACTION', {
        'action': 'open_details_expanded_origin_non_payment',
        'candidateId': resolveCandidateId,
      });
      navTrace('CONTACT_RESTORE_END', {
        'candidateId': resolveCandidateId,
        'visibleUiContext': 'candidate_details',
      });
      clearPendingOrigin(reason: 'restore_expanded_origin_non_payment');
      RuntimeFlowLogger.mark('CONTACT_RESTORE_CONTEXT_CLEARED', <String, Object?>{
        'reason': 'expanded_resume_non_payment',
        'resolvedKey': reopenGuard,
        'candidateId': resolveCandidateId,
      });
      return ContactRestoreDisposition.expandedDetailsRestored;
    }

    navTrace('CONTACT_RESTORE_ACTION', {
      'action': 'keep_compact_context_after_payment',
      'candidateId': resolveCandidateId,
    });
    navTrace('CONTACT_RESTORE_END', {
      'candidateId': resolveCandidateId,
      'visibleUiContext': 'compact_card_context',
    });
    clearPendingOrigin(reason: 'restore_after_paywall_exit_complete');
    return ContactRestoreDisposition.compactContextRestored;
    } finally {
      endPaymentRestoreSignal();
    }
  }

  Future<ContactRestoreDisposition> debugVerifyRestoreAfterPayment(
    BuildContext context, {
    required String candidateId,
    String? canonicalCandidateId,
    String? candidateUid,
    ContactUnlockSource source = ContactUnlockSource.expandedCandidateCard,
    Future<void> Function(
      String candidateId,
      String? canonicalId,
      String candidateUid,
    )?
    onExpandedRestore,
  }) async {
    if (!kDebugMode) {
      return ContactRestoreDisposition.noOrigin;
    }

    final rawCandidateId = candidateId.trim();
    final resolvedKey = resolveCandidateContactKey(
      candidateId: rawCandidateId,
      candidateKey: (candidateUid ?? rawCandidateId).trim(),
      canonicalCandidateId: canonicalCandidateId,
    ).trim();
    final canonical = (canonicalCandidateId ?? '').trim().isNotEmpty
        ? canonicalCandidateId!.trim()
        : resolvedKey;
    final resolvedUid = (candidateUid ?? '').trim().isNotEmpty
        ? candidateUid!.trim()
        : rawCandidateId;

    if (resolvedKey.isNotEmpty && rawCandidateId.isNotEmpty) {
      registerCanonicalMapping(
        canonicalCandidateId: resolvedKey,
        candidateId: rawCandidateId,
      );
    }

    setPendingOrigin(
      ContactUnlockOriginContext(
        source: source,
        candidateId: rawCandidateId,
        candidateUid: resolvedUid,
        canonicalId: canonical,
        resolvedKey: resolvedKey,
      ),
    );

    _logDebug(
      '[DEBUG_CONTACT_RESTORE_VERIFY_START] '
      'candidateId=$rawCandidateId '
      'canonicalId=$canonical '
      'sourceType=${source.name}',
    );

    final disposition = await restoreAfterPaywallExit(
      context,
      purchased: true,
      onExpandedRestore: onExpandedRestore,
    );

    final hasAccess =
        resolvedKey.isNotEmpty && hasAccessToCandidateContact(resolvedKey);
    final hasContact =
        resolvedKey.isNotEmpty && contactForCandidate(resolvedKey) != null;
    _logDebug(
      '[DEBUG_CONTACT_RESTORE_VERIFY_DONE] '
      'hasAccess=$hasAccess hasContact=$hasContact disposition=${disposition.name}',
    );

    return disposition;
  }
}
