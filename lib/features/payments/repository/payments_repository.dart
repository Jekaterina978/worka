import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:worka/core/platform/web_origin.dart';
import 'package:worka/services/env_config.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/services/auth_continuation_store.dart';
import 'package:worka/services/candidate_identity_resolver.dart';
import 'package:worka/services/ownership_context.dart';
import 'package:worka/services/runtime_flow_logger.dart';

import '../domain/models/credits_models.dart';
import '../models/checkout_session_status.dart';
import '../models/employer_payment_models.dart';
import '../models/payment_intent_response.dart';
import '../models/vacancy_payment_feature.dart';
import 'package:worka/models/job_entitlements.dart';
import '../contact_access_web_storage_backend_stub.dart'
    if (dart.library.html) '../contact_access_web_storage_backend_web.dart'
    as guest_storage;

/// Firestore CV doc id from merged payment resume map (excludes canonical UUID).
String stableFirestoreCvIdFromPaymentResumeMap(Map<String, dynamic> m) {
  String t(dynamic v) => (v ?? '').toString().trim();
  for (final key in <String>['rawCandidateId', 'cvId', 'candidateId']) {
    final v = t(m[key]);
    if (v.isNotEmpty && !CandidateIdentityResolver.isUuid(v)) return v;
  }
  return '';
}

class CandidateCanonicalResolveResult {
  const CandidateCanonicalResolveResult({
    required this.canonicalCandidateId,
    required this.matchedBy,
  });

  final String canonicalCandidateId;
  final String matchedBy;

  bool get isResolved => canonicalCandidateId.isNotEmpty;
}

class PaymentsRepository {
  PaymentsRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _kAuthRestoreTimeout = Duration(seconds: 8);
  static const String _kGuestSessionStorageKey = 'worka_guest_session_id_v1';

  String get _baseUrl {
    final resolved = EnvConfig.paymentsApiBaseUrl(
      allowDevFallback: !kReleaseMode,
    );
    if (resolved == null || resolved.isEmpty) {
      throw StateError(
        'PAYMENTS_API_BASE_URL or WORKA_API_BASE_URL must be set via --dart-define',
      );
    }
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] resolvedBaseUrl=$resolved');
    }
    return resolved;
  }

  Future<User> _requireSignedInUser({required String reason}) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return user;

    RuntimeFlowLogger.mark('PAYMENT_AUTH_WAIT_START', <String, Object?>{
      'reason': reason,
      'uid': (user?.uid ?? '').trim(),
      'isAnonymous': user?.isAnonymous ?? false,
      'timeoutMs': _kAuthRestoreTimeout.inMilliseconds,
    });
    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] waiting for FirebaseAuth restore before $reason',
      );
    }
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((candidate) => candidate != null && !candidate.isAnonymous)
          .timeout(_kAuthRestoreTimeout);
    } catch (error) {
      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        RuntimeFlowLogger.mark('PAYMENT_AUTH_WAIT_TIMEOUT', <String, Object?>{
          'reason': reason,
          'error': error.toString(),
          'timeoutMs': _kAuthRestoreTimeout.inMilliseconds,
        });
        throw StateError(
          'User session is required for $reason, but auth was not restored in time.',
        );
      }
    }

    if (user == null || user.isAnonymous) {
      RuntimeFlowLogger.mark('PAYMENT_AUTH_WAIT_TIMEOUT', <String, Object?>{
        'reason': reason,
        'error': 'auth_unavailable_or_anonymous',
        'timeoutMs': _kAuthRestoreTimeout.inMilliseconds,
      });
      throw StateError(
        'Anonymous session is not allowed for $reason. Please sign in.',
      );
    }
    RuntimeFlowLogger.mark('PAYMENT_AUTH_WAIT_OK', <String, Object?>{
      'reason': reason,
      'uid': user.uid,
      'isAnonymous': user.isAnonymous,
    });
    return user;
  }

  Future<String> _authToken() async {
    final user = await _requireSignedInUser(reason: 'payments API');
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Failed to get Firebase ID token.');
    }
    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] auth token attached: yes; uid=${user.uid}; anon=${user.isAnonymous}',
      );
    }
    return token;
  }

  Future<String> _authTokenGuestContactOnly() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous || user.uid.trim().isEmpty) {
      throw StateError(
        'Guest contact checkout requires an anonymous Firebase session.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Failed to get Firebase ID token for guest.');
    }
    return token;
  }

  String _guestSessionId() {
    final existing = guest_storage.localStorageGet(_kGuestSessionStorageKey);
    final clean = (existing ?? '').trim();
    if (clean.isNotEmpty) return clean;
    final generated =
        'g_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
    guest_storage.localStorageSet(_kGuestSessionStorageKey, generated);
    return generated;
  }

  /// Reads stored guest session without generating a new id (payment-return safe).
  String peekGuestSessionId() {
    final existing = guest_storage.localStorageGet(_kGuestSessionStorageKey);
    return (existing ?? '').trim();
  }

  String getOrCreateGuestSessionId() => _guestSessionId();

  /// Force-restore the guest session id (e.g. from a payment return URL).
  /// Must only be called when an authoritative value is recovered from a
  /// trusted source (Stripe success URL or persisted payment context). This
  /// guarantees post-payment unlock reads target the same `buyer_guest_id`
  /// the checkout was created against.
  void restoreGuestSessionId(
    String authoritativeId, {
    String restoreSource = 'payment_return',
  }) {
    final clean = authoritativeId.trim();
    if (clean.isEmpty) return;
    final existing = (guest_storage.localStorageGet(_kGuestSessionStorageKey) ?? '')
        .trim();
    if (existing == clean) return;
    guest_storage.localStorageSet(_kGuestSessionStorageKey, clean);
    RuntimeFlowLogger.mark('GUEST_SESSION_RESTORED', <String, Object?>{
      'previous': existing,
      'restored': clean,
      'changed': existing != clean,
      'restoreSource': restoreSource,
    });
  }

  bool _shouldUseGuestContactEmployerHeaders() {
    final u = FirebaseAuth.instance.currentUser;
    if (app_mode.AppMode.currentMode == app_mode.AccountMode.business) {
      return false;
    }
    if (u != null && !u.isAnonymous && u.uid.trim().isNotEmpty) return false;
    if (u != null && u.isAnonymous && u.uid.trim().isNotEmpty) return true;
    return _guestSessionId().trim().isNotEmpty;
  }

  bool _isGuestCheckoutModeForContact() {
    final u = FirebaseAuth.instance.currentUser;
    return (u == null || u.isAnonymous) &&
        app_mode.AppMode.currentMode != app_mode.AccountMode.business;
  }

  ({String buyerOwnerType, String buyerOwnerId, String buyerSig, String uid, String companyId, String mode})
  resolveContactBuyerScope() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final isBusiness =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final companyId = isBusiness ? app_mode.AppMode.activeCompanyId.trim() : '';
    if (user == null || user.isAnonymous || uid.isEmpty) {
      RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_BLOCKED', <String, Object?>{
        'mode': isBusiness ? 'business' : 'personal',
        'uid': uid,
        'activeCompanyId': companyId,
        'reason': 'auth_required_or_not_ready',
        'source': 'payments_repository.resolveContactBuyerScope',
      });
      throw StateError('auth_required_or_not_ready');
    }
    if (isBusiness && companyId.isEmpty) {
      RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_BLOCKED', <String, Object?>{
        'mode': 'business',
        'uid': uid,
        'activeCompanyId': companyId,
        'reason': 'missing_active_company_id',
        'source': 'payments_repository.resolveContactBuyerScope',
      });
      throw StateError('missing_active_company_id');
    }
    final ownerType = isBusiness ? 'business' : 'personal';
    final ownerId = isBusiness ? companyId : uid;
    return (
      buyerOwnerType: ownerType,
      buyerOwnerId: ownerId,
      buyerSig: '$ownerType|$ownerId',
      uid: uid,
      companyId: companyId,
      mode: isBusiness ? 'business' : 'personal',
    );
  }

  Future<Map<String, String>> _guestContactHeaders({
    bool json = true,
    bool requireAuthToken = false,
  }) async {
    String token = '';
    String uid = '';
    if (requireAuthToken) {
      token = await _authTokenGuestContactOnly();
      uid = FirebaseAuth.instance.currentUser!.uid.trim();
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.isAnonymous && user.uid.trim().isNotEmpty) {
        uid = user.uid.trim();
        try {
          token = (await user.getIdToken())?.trim() ?? '';
        } catch (_) {}
      }
    }
    final guestSessionId = _guestSessionId().trim();
    if (guestSessionId.isEmpty) {
      RuntimeFlowLogger.mark('GUEST_CONTACT_SCOPE_MISSING', <String, Object?>{
        'source': 'payments_repository._guestContactHeaders',
        'reason': 'guest_session_id_required',
      });
      throw StateError(
        'Guest contact API calls require a stable guest session id (g_…).',
      );
    }
    final buyerGuestKey = guestSessionId;
    final buyerSig = 'guest|$guestSessionId';
    RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_RESOLVE', <String, Object?>{
      'source': 'payments_repository._guestContactHeaders',
      'buyerOwnerType': 'guest',
      'buyerOwnerId': buyerGuestKey,
      'buyerSig': buyerSig,
      'uid': uid,
      'guestSessionId': guestSessionId,
      'companyId': '',
      'mode': 'guest',
    });
    return <String, String>{
      if (json) HttpHeaders.contentTypeHeader: 'application/json',
      if (token.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $token',
      'x-owner-type': 'guest',
      'x-owner-id': buyerGuestKey,
      if (uid.isNotEmpty) 'x-user-id': uid,
      'x-guest-checkout': 'true',
      'x-guest-session-id': guestSessionId,
    };
  }

  Future<Map<String, String>> _headers({
    bool json = true,
    String? requiredBusinessCompanyId,
  }) async {
    final token = await _authToken();
    final userId = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isBusiness =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    String companyId = isBusiness ? app_mode.AppMode.activeCompanyId : '';
    final requiredCompanyId = (requiredBusinessCompanyId ?? '').trim();
    if (requiredCompanyId.isNotEmpty) {
      final businessOwnership =
          CanonicalOwnershipResolver.resolveBusinessPaymentOwner(
            actionLabel: 'payments_headers',
            expectedCompanyId: requiredCompanyId,
          );
      companyId = businessOwnership.ownerId;
    }
    if (kDebugMode) {
      debugPrint(
        '[PAYMENT_HEADERS_SCOPE] mode=${isBusiness ? 'business' : 'personal'} '
        'userId=$userId companyId=$companyId '
        'hasCompany=${companyId.isNotEmpty} requiredCompanyId=$requiredCompanyId',
      );
    }
    final scope = resolveContactBuyerScope();
    final ownerType = scope.buyerOwnerType;
    final ownerId = ownerType == 'business' ? companyId : scope.buyerOwnerId;
    RuntimeFlowLogger.mark('PAYMENT_HEADERS_SCOPE', <String, Object?>{
      'mode': isBusiness ? 'business' : 'personal',
      'uid': userId,
      'companyId': companyId,
      'ownerType': ownerType,
      'ownerId': ownerId,
      'hasCompany': companyId.isNotEmpty,
      'requiredCompanyId': requiredCompanyId,
    });
    RuntimeFlowLogger.mark('CONTACT_BUYER_SCOPE_RESOLVE', <String, Object?>{
      'source': 'payments_repository._headers',
      'buyerOwnerType': ownerType,
      'buyerOwnerId': ownerId,
      'buyerSig': scope.buyerSig,
      'uid': scope.uid,
      'companyId': scope.companyId,
      'mode': scope.mode,
    });
    return <String, String>{
      if (json) HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'x-owner-type': ownerType,
      if (ownerId.isNotEmpty) 'x-owner-id': ownerId,
      if (userId.isNotEmpty) 'x-user-id': userId,
      if (companyId.isNotEmpty) 'x-company-id': companyId,
    };
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<JobEntitlements> fetchJobEntitlements(String jobCode) async {
    final uri = _uri('/jobs/$jobCode/entitlements');
    final headers = await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    final json = _decodeObject(response.body);
    return JobEntitlements.fromJson(json);
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<void> _throwIfFailed(
    http.Response response, {
    required Uri uri,
  }) async {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String msg = 'Request failed (${response.statusCode})';
    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] ${uri.path} -> status=${response.statusCode} body=${response.body}',
      );
    }
    try {
      final json = _decodeObject(response.body);
      final err = (json['error'] ?? '').toString().trim();
      if (err.isNotEmpty) msg = err;
    } catch (_) {}
    throw StateError(msg);
  }

  Future<EmployerMe> getEmployerMe() async {
    final uri = _uri('/employer/me');
    final headers = await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    return EmployerMe.fromJson(_decodeObject(response.body));
  }

  Future<EmployerWallet> getAuthoritativeEmployerWalletState() async {
    final uri = _uri('/employer/credits/state');
    final fallbackUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final isBusinessMode =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final ownerType = isBusinessMode ? 'business' : 'personal';
    final ownerId = isBusinessMode
        ? app_mode.AppMode.activeCompanyId.trim()
        : fallbackUid;
    final companyId = app_mode.AppMode.activeCompanyId.trim();
    RuntimeFlowLogger.mark('CONTACT_WALLET_LOAD_START', <String, Object?>{
      'url': uri.toString(),
      'ownerType': ownerType,
      'ownerId': ownerId,
      'uid': fallbackUid,
      'companyId': companyId,
    });
    final headers = await _headers(
      json: false,
      requiredBusinessCompanyId: isBusinessMode ? ownerId : null,
    );
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      RuntimeFlowLogger.mark('CONTACT_WALLET_LOAD_FAILED', <String, Object?>{
        'url': uri.toString(),
        'status': response.statusCode,
        'responseBody': response.body,
        'ownerType': ownerType,
        'ownerId': ownerId,
        'uid': fallbackUid,
        'companyId': companyId,
      });
      if (kDebugMode) {
        debugPrint(
          '[CONTACT_WALLET_LOAD_FAILED] url=$uri status=${response.statusCode} '
          'ownerType=$ownerType ownerId=$ownerId uid=$fallbackUid companyId=$companyId '
          'body=${response.body}',
        );
      }
      await _throwIfFailed(response, uri: uri);
    }
    final json = _decodeObject(response.body);
    final wallet = (json['wallet'] is Map<String, dynamic>)
        ? json['wallet'] as Map<String, dynamic>
        : (json['wallet'] is Map)
        ? Map<String, dynamic>.from(json['wallet'] as Map)
        : const <String, dynamic>{};
    final uid = (json['uid'] ?? fallbackUid).toString().trim();
    final rawCredits =
        wallet['creditsBalance'] ?? json['creditsBalance'] ?? json['credits'];
    int credits = 0;
    if (rawCredits is int) {
      credits = rawCredits;
    } else if (rawCredits is num) {
      credits = rawCredits.toInt();
    } else if (rawCredits != null) {
      credits = int.tryParse(rawCredits.toString()) ?? 0;
    }
    final rawIds = (json['candidateIds'] is List)
        ? json['candidateIds'] as List
        : const [];
    final resolvedWallet = EmployerWallet(
      uid: uid,
      balance: credits,
      unlockedCandidateIds: rawIds
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet(),
      fetchedAt: DateTime.now(),
    );
    RuntimeFlowLogger.mark('CONTACT_WALLET_LOAD_OK', <String, Object?>{
      'url': uri.toString(),
      'status': response.statusCode,
      'ownerType': ownerType,
      'ownerId': ownerId,
      'uid': fallbackUid,
      'companyId': companyId,
      'creditsBalance': resolvedWallet.balance,
      'unlockedCount': resolvedWallet.unlockedCandidateIds.length,
    });
    return resolvedWallet;
  }

  Future<Map<String, String>> _headersBestEffort({bool json = true}) async {
    try {
      return await _headers(json: json);
    } catch (_) {
      return <String, String>{
        if (json) HttpHeaders.contentTypeHeader: 'application/json',
      };
    }
  }

  Future<List<CreditHistoryItem>> getCreditsHistory() async {
    final uri = _uri('/employer/credits/history');
    final headers = await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    final root = _decodeObject(response.body);
    final raw = (root['items'] is List) ? root['items'] as List : const [];
    return raw
        .whereType<Map>()
        .map((e) => CreditHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> createPaymentIntent({
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? context,
    String? vatId,
  }) async {
    final payload = await createPaymentIntentPayload(
      productId: productId,
      quantity: quantity,
      context: context,
      vatId: vatId,
    );
    return payload.clientSecret;
  }

  Future<PaymentIntentResponse> createPaymentIntentPayload({
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? context,
    String? vatId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[PAYMENT] openPaymentFlow createPaymentIntent productId=$productId qty=$quantity context=$context vatId=$vatId',
      );
    }
    final body = <String, dynamic>{
      'productId': productId,
      'quantity': quantity,
      if (context != null) 'context': context,
      if ((vatId ?? '').trim().isNotEmpty) 'vatId': vatId!.trim(),
    };

    final uri = _uri('/payments/create-payment-intent');
    final headers = await _headers();
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] POST $uri');
    }
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    await _throwIfFailed(response, uri: uri);
    final data = _decodeObject(response.body);
    return PaymentIntentResponse.fromJson(data);
  }

  Future<String> createCheckoutSessionUrl({
    required String productId,
    required int amountCents,
    String currency = 'EUR',
    String? ownerId,
    String ownerType = 'user',
    String? targetId, // canonical candidate UUID for contact unlock (backend target)
    String? targetType,
    String? sourceScreen,
    String? returnMode,
    /// Firestore CV doc id for contact checkout — must not be UUID / canonical.
    String? contactRawCvDocId,
  }) async {
    final isContactCheckout =
        productId == 'contact_1' ||
        productId == 'contact_10' ||
        productId == 'contact_30';
    RuntimeFlowLogger.mark('CHECKOUT_CREATE_START', <String, Object?>{
      'productId': productId,
      'ownerType': ownerType,
      'ownerId': (ownerId ?? '').trim(),
      'targetType': (targetType ?? '').trim(),
      'targetId': (targetId ?? '').trim(),
      'sourceScreen': (sourceScreen ?? '').trim(),
      'returnMode': (returnMode ?? '').trim(),
    });
    try {
      if (kDebugMode) {
        debugPrint('[PAYMENT DEBUG] START createCheckoutSessionUrl');
        debugPrint('[PAYMENT DEBUG] featureKey=$productId');
        debugPrint('[PAYMENT DEBUG] ownerType=$ownerType');
        debugPrint('[PAYMENT DEBUG] ownerId=${ownerId ?? ''}');
        debugPrint('[PAYMENT DEBUG] targetType=${targetType ?? ''}');
        debugPrint('[PAYMENT DEBUG] targetId=${targetId ?? ''}');
        debugPrint('[PAYMENT DEBUG] amountCents=$amountCents');
      }
      final returnOrigin = getCurrentOrigin();
      if (returnOrigin.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[PAYMENT DEBUG] returnOrigin=$returnOrigin');
        }
      }

      final currentFirebase = FirebaseAuth.instance.currentUser;
      final isAnon = currentFirebase?.isAnonymous ?? false;
      final tt = (targetType ?? '').trim();
      final tid = (targetId ?? '').trim();
      if (isContactCheckout &&
          (isAnon || currentFirebase == null) &&
          app_mode.AppMode.currentMode != app_mode.AccountMode.business &&
          (productId != 'contact_1' || tt != 'candidate' || tid.isEmpty)) {
        RuntimeFlowLogger.mark('GUEST_CONTACT_CHECKOUT_BLOCKED', <String, Object?>{
          'reason': 'anonymous_requires_contact_1_candidate',
          'productId': productId,
          'targetType': tt,
          'targetId': tid,
        });
        throw StateError(
          'Войдите в аккаунт, чтобы купить выбранный пакет контактов.',
        );
      }
      final guestContactOneCheckout = isContactCheckout &&
          productId == 'contact_1' &&
          tt == 'candidate' &&
          tid.isNotEmpty &&
          (isAnon || currentFirebase == null) &&
          app_mode.AppMode.currentMode != app_mode.AccountMode.business;
      if (guestContactOneCheckout) {
        RuntimeFlowLogger.mark('GUEST_CHECKOUT_START', <String, Object?>{
          'productId': productId,
          'targetId': tid,
        });
        RuntimeFlowLogger.mark('AUTH_GATE_SKIPPED_FOR_GUEST_CONTACT_1', <String, Object?>{
          'productId': productId,
          'targetId': tid,
          'source': 'payments_repository.createCheckoutSessionUrl',
        });
        RuntimeFlowLogger.mark('GUEST_CONTACT_CHECKOUT_ALLOWED', <String, Object?>{
          'productId': productId,
          'targetType': tt,
          'targetId': tid,
          'uid': currentFirebase?.uid ?? '',
          'guestSessionId': _guestSessionId(),
        });
      }
      final User? restoredUser = guestContactOneCheckout
          ? currentFirebase
          : await _requireSignedInUser(reason: 'checkout');
      final requestedOwnerType = ownerType.trim().toLowerCase();
      final requestedOwnerId = (ownerId ?? '').trim();
      final isCvPromoCheckout =
          productId == 'highlight_cv_7d' ||
          productId == 'cv_boost_7d' ||
          productId == 'priority_cv_7d';
      if (isCvPromoCheckout) {
        debugPrint(
          '[CV_PROMO_CHECKOUT_SCOPE] mode=${app_mode.AppMode.currentMode.name} ownerType=$requestedOwnerType ownerId=$requestedOwnerId uid=${restoredUser?.uid ?? ''}',
        );
      }
      final contactOwnership = isContactCheckout
          ? (guestContactOneCheckout
                ? <String, String>{
                    'ownerType': 'guest',
                    'ownerId': _guestSessionId(),
                  }
                : <String, String>{
                    'ownerType':
                        app_mode.AppMode.currentMode == app_mode.AccountMode.business
                        ? 'company'
                        : 'user',
                    'ownerId': app_mode.AppMode.currentMode ==
                            app_mode.AccountMode.business
                        ? app_mode.AppMode.activeCompanyId.trim()
                        : (restoredUser?.uid ?? ''),
                  })
          : null;
      if (isContactCheckout) {
        RuntimeFlowLogger.mark('CHECKOUT_SCOPE_RESOLVE', <String, Object?>{
          'productId': productId,
          'resolvedOwnerType': contactOwnership!['ownerType'],
          'resolvedOwnerId': contactOwnership['ownerId'],
          'targetType': (targetType ?? '').trim(),
          'targetId': (targetId ?? '').trim(),
        });
        RuntimeFlowLogger.mark('CHECKOUT_SCOPE_OK', <String, Object?>{
          'productId': productId,
          'ownerType': contactOwnership['ownerType'],
          'ownerId': contactOwnership['ownerId'],
        });
      }

      final effectiveOwnerId = isContactCheckout
          ? (contactOwnership!['ownerId'] ?? '')
          : (requestedOwnerId.isNotEmpty
                ? requestedOwnerId
                : (restoredUser?.uid ?? ''));
      final effectiveTargetId = (targetId ?? '').trim();
      final effectiveTargetType = (targetType ?? '').trim();
      if (effectiveOwnerId.isEmpty) {
        RuntimeFlowLogger.mark('CHECKOUT_CREATE_FAILED', <String, Object?>{
          'reason': 'missing_owner',
          'productId': productId,
          'ownerType': ownerType,
          'ownerId': (ownerId ?? '').trim(),
        });
        if (kDebugMode) {
          debugPrint(
            '[PAYMENT DEBUG] ERROR blocked: missing owner '
            'ownerId=$effectiveOwnerId featureKey=$productId',
          );
        }
        throw StateError('Missing owner for checkout.');
      }
      final hasTargetId = effectiveTargetId.isNotEmpty;
      final hasTargetType = effectiveTargetType.isNotEmpty;
      if (hasTargetId != hasTargetType) {
        RuntimeFlowLogger.mark('CHECKOUT_CREATE_FAILED', <String, Object?>{
          'reason': 'invalid_target_contract',
          'productId': productId,
          'targetType': effectiveTargetType,
          'targetId': effectiveTargetId,
        });
        if (kDebugMode) {
          debugPrint(
            '[PAYMENT DEBUG] ERROR blocked: inconsistent target contract '
            'targetType=$effectiveTargetType targetId=$effectiveTargetId featureKey=$productId',
          );
        }
        throw StateError('Invalid target contract for checkout.');
      }
      if (effectiveTargetType == 'candidate' && !hasTargetId) {
        RuntimeFlowLogger.mark('CHECKOUT_CREATE_FAILED', <String, Object?>{
          'reason': 'missing_candidate_target',
          'productId': productId,
        });
        if (kDebugMode) {
          debugPrint(
            '[PAYMENT DEBUG] ERROR blocked: candidate checkout without candidate target '
            'featureKey=$productId',
          );
        }
        throw StateError(
          'Missing candidate target for direct unlock checkout.',
        );
      }

      final guestSessionIdForContext = guestContactOneCheckout
          ? _guestSessionId()
          : '';

      final priorPaymentRaw =
          AuthContinuationStore.instance.peekPendingPaymentReturnContextPayloadRaw();
      final stripeResumePatch = <String, dynamic>{
        'mode': (returnMode ?? '').trim(),
        'source': (sourceScreen ?? '').trim(),
        'sourceScreen': (sourceScreen ?? '').trim(),
        'selectedProductId': productId,
        'ownerType':
            (isContactCheckout ? contactOwnership!['ownerType'] : requestedOwnerType)
                .toString(),
        'ownerId': effectiveOwnerId,
        'guestSessionId': guestSessionIdForContext,
        'guest_session_id': guestSessionIdForContext,
        'returnMode': (returnMode ?? '').trim(),
        'checkoutSessionId': '',
        'sessionId': '',
      };
      if (effectiveTargetType == 'candidate' && hasTargetId) {
        stripeResumePatch['canonicalId'] = effectiveTargetId;
        stripeResumePatch['canonicalCandidateId'] = effectiveTargetId;
        stripeResumePatch['restoreKey'] = effectiveTargetId;
        final explicitRaw = (contactRawCvDocId ?? '').trim();
        if (explicitRaw.isNotEmpty &&
            !CandidateIdentityResolver.isUuid(explicitRaw)) {
          stripeResumePatch['candidateId'] = explicitRaw;
          stripeResumePatch['cvId'] = explicitRaw;
          stripeResumePatch['rawCandidateId'] = explicitRaw;
        }
      } else if (effectiveTargetType == 'cv' && hasTargetId) {
        stripeResumePatch['cvId'] = effectiveTargetId;
      } else if (effectiveTargetType == 'job' && hasTargetId) {
        stripeResumePatch['jobId'] = effectiveTargetId;
      }

      final mergedResumePreview = AuthContinuationStore.mergePaymentReturnPayload(
        priorPaymentRaw,
        stripeResumePatch,
      );
      final contactCheckoutRawCv =
          effectiveTargetType == 'candidate' && hasTargetId
          ? stableFirestoreCvIdFromPaymentResumeMap(mergedResumePreview)
          : '';

      if (effectiveTargetType == 'candidate' &&
          hasTargetId &&
          contactCheckoutRawCv.isEmpty) {
        RuntimeFlowLogger.mark(
          'PAYMENT_RETURN_CONTEXT_MISSING',
          <String, Object?>{
            'missing': 'rawCandidateId,cvId,candidateId',
            'canonicalId': effectiveTargetId,
            'checkoutSessionId': '',
            'phase': 'checkout_create_presubmit',
            'source': 'payments_repository.createCheckoutSessionUrl',
          },
        );
      }

      final returnContext = <String, dynamic>{
        if ((returnMode ?? '').trim().isNotEmpty) 'mode': returnMode!.trim(),
        if ((sourceScreen ?? '').trim().isNotEmpty)
          'source_screen': sourceScreen!.trim(),
        if (effectiveTargetType == 'cv' && hasTargetId)
          'cv_id': effectiveTargetId,
        if (effectiveTargetType == 'job' && hasTargetId)
          'job_id': effectiveTargetId,
      };
      if (effectiveTargetType == 'candidate' && hasTargetId) {
        returnContext['canonical_candidate_id'] = effectiveTargetId;
        if (contactCheckoutRawCv.isNotEmpty) {
          returnContext['candidate_id'] = contactCheckoutRawCv;
          returnContext['raw_candidate_id'] = contactCheckoutRawCv;
          returnContext['cv_id'] = contactCheckoutRawCv;
        }
      }

      final body = <String, dynamic>{
        'feature_key': productId,
        'productId': productId,
        'amount': amountCents / 100,
        'amount_cents': amountCents,
        'currency': currency,
        'owner_type': isContactCheckout
            ? contactOwnership!['ownerType']
            : requestedOwnerType,
        'owner_id': effectiveOwnerId,
        if (guestContactOneCheckout) 'guest_session_id': _guestSessionId(),
        if (hasTargetType) 'target_type': effectiveTargetType,
        if (hasTargetId) 'target_id': effectiveTargetId,
        'context': <String, dynamic>{'origin': 'checkout_generic'},
        if (returnOrigin.isNotEmpty) 'return_origin': returnOrigin,
        'return_context': returnContext,
      };
      await AuthContinuationStore.instance
          .savePendingPaymentReturnContextMerged(stripeResumePatch);
      if (isContactCheckout && kDebugMode) {
        debugPrint(
          '[PAYMENT DEBUG] contact checkout body owner_type=${body['owner_type']} owner_id=${body['owner_id']} target_type=${body['target_type'] ?? ''} target_id=${body['target_id'] ?? ''}',
        );
      }
      final uri = _uri('/payments/checkout');
      if (isContactCheckout) {
        RuntimeFlowLogger.mark('CONTACT_CHECKOUT_START', <String, Object?>{
          'url': uri.toString(),
          'ownerType': body['owner_type'],
          'ownerId': body['owner_id'],
          'targetType': body['target_type'] ?? '',
          'targetId': body['target_id'] ?? '',
          'productId': productId,
        });
        RuntimeFlowLogger.mark(
          'CONTACT_CHECKOUT_CREATE_START',
          <String, Object?>{
            'url': uri.toString(),
            'ownerType': body['owner_type'],
            'ownerId': body['owner_id'],
            'targetType': body['target_type'] ?? '',
            'targetId': body['target_id'] ?? '',
            'productId': productId,
            'uid': restoredUser?.uid ?? '',
            'companyId': app_mode.AppMode.activeCompanyId.trim(),
          },
        );
      }

      if (kDebugMode) {
        debugPrint(
          '[API_FETCH_START] method=POST uri=$uri kind=checkout_create',
        );
        debugPrint('[PAYMENT DEBUG] baseUrl=$_baseUrl');
        debugPrint('[PAYMENT DEBUG] endpoint=/payments/checkout');
        debugPrint('[PAYMENT DEBUG] body=${jsonEncode(body)}');
      }

      final headers = guestContactOneCheckout
          ? await _guestContactHeaders()
          : await _headers(
              requiredBusinessCompanyId:
                  isContactCheckout &&
                      contactOwnership!['ownerType'] == 'company'
                  ? (contactOwnership['ownerId'] ?? '')
                  : null,
            );

      if (guestContactOneCheckout) {
        RuntimeFlowLogger.mark('GUEST_CONTACT_PAYMENT_SESSION_CREATE', <String, Object?>{
          'productId': productId,
          'targetId': tid,
          'guestSessionId': _guestSessionId(),
        });
      }

      final response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      if (kDebugMode) {
        debugPrint('[PAYMENT DEBUG] status=${response.statusCode}');
        debugPrint('[PAYMENT DEBUG] response=${response.body}');
      }

      await _throwIfFailed(response, uri: uri);
      final data = _decodeObject(response.body);
      final url = (data['url'] ?? '').toString().trim();
      final createdSessionId = (data['sessionId'] ?? '').toString().trim();
      if (url.isEmpty) {
        RuntimeFlowLogger.mark('CHECKOUT_CREATE_FAILED', <String, Object?>{
          'reason': 'missing_checkout_url',
          'productId': productId,
          'statusCode': response.statusCode,
        });
        if (kDebugMode) {
          debugPrint(
            '[PAYMENT DEBUG] ERROR missing url in response body=${response.body}',
          );
        }
        throw StateError('Missing checkout url in response.');
      }

      if (kDebugMode) {
        debugPrint('[PAYMENT DEBUG] checkoutUrl=$url');
      }
      RuntimeFlowLogger.mark('CHECKOUT_CREATE_OK', <String, Object?>{
        'productId': productId,
        'ownerType': body['owner_type'],
        'ownerId': body['owner_id'],
        'targetType': body['target_type'] ?? '',
        'targetId': body['target_id'] ?? '',
        'statusCode': response.statusCode,
        'checkoutSessionId': createdSessionId,
      });
      await AuthContinuationStore.instance.savePendingPaymentReturnContextMerged(
        <String, dynamic>{
          'checkoutSessionId': createdSessionId,
          'sessionId': createdSessionId,
        },
      );
      RuntimeFlowLogger.mark('CHECKOUT_URL_OPEN', <String, Object?>{
        'productId': productId,
        'url': url,
      });
      if (isContactCheckout) {
        RuntimeFlowLogger.mark('CONTACT_CHECKOUT_OK', <String, Object?>{
          'url': url,
          'productId': productId,
          'targetId': body['target_id'] ?? '',
          'ownerId': body['owner_id'],
        });
        if (guestContactOneCheckout) {
          RuntimeFlowLogger.mark('GUEST_CHECKOUT_SUCCESS', <String, Object?>{
            'productId': productId,
            'targetId': tid,
          });
        }
      }
      return url;
    } catch (e) {
      if (isContactCheckout) {
        RuntimeFlowLogger.mark(
          'CONTACT_CHECKOUT_CREATE_FAILED',
          <String, Object?>{
            'url': _uri('/payments/checkout').toString(),
            'ownerType': ownerType,
            'ownerId': (ownerId ?? '').trim(),
            'targetType': (targetType ?? '').trim(),
            'targetId': (targetId ?? '').trim(),
            'productId': productId,
            'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
            'companyId': app_mode.AppMode.activeCompanyId.trim(),
            'error': e.toString(),
          },
        );
      }
      RuntimeFlowLogger.mark('GUEST_CHECKOUT_FAIL', <String, Object?>{
        'productId': productId,
        'targetId': (targetId ?? '').trim(),
        'error': e.toString(),
      });
      RuntimeFlowLogger.mark('CHECKOUT_CREATE_FAILED', <String, Object?>{
        'reason': 'exception',
        'productId': productId,
        'error': e.toString(),
      });
      if (kDebugMode) {
        debugPrint(
          '[API_FETCH_ERROR] method=POST uri=${_uri('/payments/checkout')} error=$e',
        );
        debugPrint('[PAYMENT DEBUG] ERROR=$e');
      }
      rethrow;
    }
  }

  Future<String> createVacancyCheckoutSessionUrl({
    required String canonicalProductId,
    required String jobId,
    required String entityOwnerType,
    required String entityOwnerId,
    Map<String, dynamic>? context,
    String? returnOrigin,
    String? sourceScreen,
  }) async {
    final spec = VacancyPaymentFeatures.byAnyId(canonicalProductId);
    if (spec == null) {
      throw StateError(
        'Unsupported vacancy product for checkout: $canonicalProductId',
      );
    }
    final trimmedJobId = jobId.trim();
    if (trimmedJobId.isEmpty) {
      throw StateError('Missing jobCode for vacancy checkout.');
    }
    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] vacancy checkout begin canonicalProductId=${spec.canonicalId} backendProductId=${spec.backendProductId} jobId=$trimmedJobId',
      );
      if ((returnOrigin ?? '').trim().isNotEmpty) {
        debugPrint(
          '[PAYMENT DEBUG] vacancy returnOrigin=${returnOrigin!.trim()} targetId=$trimmedJobId featureKey=${spec.backendProductId}',
        );
      }
      if (context != null && context.isNotEmpty) {
        debugPrint('[PAYMENT DEBUG] vacancy context ignored=$context');
      }
    }
    final isBusiness =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final resolvedOwnerType = isBusiness ? 'business' : 'personal';
    final resolvedOwnerId = isBusiness
        ? app_mode.AppMode.activeCompanyId.trim()
        : (FirebaseAuth.instance.currentUser?.uid.trim() ?? '');
    if (isBusiness && resolvedOwnerId.isEmpty) {
      throw StateError(
        'Business vacancy checkout requires active company scope.',
      );
    }
    if (!isBusiness && resolvedOwnerId.isEmpty) {
      throw StateError(
        'Personal vacancy checkout requires authenticated user.',
      );
    }
    final scopeDecision = CanonicalOwnershipResolver.resolvePromotionAccess(
      entityOwnerType: entityOwnerType,
      entityOwnerId: entityOwnerId,
    );
    if (!scopeDecision.allowed) {
      debugPrint(
        '[OWNER_SCOPE_REJECT] resource=job action=promotion_checkout reason=${scopeDecision.reason} '
        'entityOwnerType=$entityOwnerType entityOwnerId=$entityOwnerId '
        'mode=${app_mode.AppMode.currentMode.name} uid=${FirebaseAuth.instance.currentUser?.uid ?? ''} '
        'activeCompanyId=${app_mode.AppMode.activeCompanyId}',
      );
      throw StateError(PromotionOwnershipDecision.mismatchMessage);
    }
    return createCheckoutSessionUrl(
      productId: spec.backendProductId,
      amountCents: spec.paymentProduct.cents,
      ownerType: resolvedOwnerType,
      ownerId: resolvedOwnerId,
      targetId: trimmedJobId,
      targetType: 'job',
      sourceScreen: sourceScreen ?? 'promote_job_screen',
      returnMode: 'job_promotion',
    );
  }

  Future<CheckoutSessionStatus> getCheckoutSessionStatus({
    required String sessionId,
  }) async {
    final safeSessionId = sessionId.trim();
    if (safeSessionId.isEmpty) {
      throw StateError('sessionId is required.');
    }

    final successUri = _uri(
      '/payments/checkout/success',
    ).replace(queryParameters: <String, String>{'session_id': safeSessionId});
    final headers = _shouldUseGuestContactEmployerHeaders()
        ? await _guestContactHeaders(json: false)
        : await _headersBestEffort(json: false);
    try {
      final response = await _client.get(successUri, headers: headers);
      await _throwIfFailed(response, uri: successUri);
      return CheckoutSessionStatus.fromJson(_decodeObject(response.body));
    } catch (_) {
      // Backward-compat fallback for older backend versions.
      final legacyUri = _uri('/payments/checkout-session-status');
      final postHeaders = _shouldUseGuestContactEmployerHeaders()
          ? await _guestContactHeaders()
          : await _headersBestEffort();
      final response = await _client.post(
        legacyUri,
        headers: postHeaders,
        body: jsonEncode(<String, dynamic>{'sessionId': safeSessionId}),
      );
      await _throwIfFailed(response, uri: legacyUri);
      return CheckoutSessionStatus.fromJson(_decodeObject(response.body));
    }
  }

  Future<ConsumeCreditResult> consumeCredit({
    required String candidateId,
  }) async {
    final uri = _uri('/employer/credits/consume');
    final headers = await _headers();
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] POST $uri');
    }
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode({'candidateId': candidateId}),
    );
    await _throwIfFailed(response, uri: uri);
    return ConsumeCreditResult.fromJson(_decodeObject(response.body));
  }

  Future<CandidateContact> getUnlockedCandidateContact({
    required String candidateId,
  }) async {
    final safeId = candidateId.trim();
    if (safeId.isEmpty) {
      throw StateError('candidateId is required.');
    }
    final uri = _uri('/employer/contacts/$safeId');
    final headers = _shouldUseGuestContactEmployerHeaders()
        ? await _guestContactHeaders(json: false)
        : await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    return CandidateContact.fromJson(_decodeObject(response.body));
  }

  Future<String> syncCandidateFromCv({
    required String cvId,
    required String name,
    String? email,
    String? phone,
    String? ownerUid,
  }) async {
    final uri = _uri('/candidates/sync-from-cv');
    final headers = await _headers();
    final body = <String, dynamic>{
      'cv_id': cvId,
      'name': name,
      'email': email,
      'phone': phone,
      'owner_uid': ownerUid,
    };
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] POST $uri sync-from-cv body=$body');
    }
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    await _throwIfFailed(response, uri: uri);
    final json = _decodeObject(response.body);
    final id = (json['candidate_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw StateError('sync-from-cv returned empty candidate_id');
    }
    return id;
  }

  Future<CandidateCanonicalResolveResult> resolveCanonicalCandidateId({
    required String rawCandidateId,
    String cvId = '',
    String candidateOwnerId = '',
    Map<String, dynamic>? candidateSnapshot,
  }) async {
    final lookupIds = CandidateIdentityResolver.collectLookupIds(
      rawCandidateId: rawCandidateId,
      cvId: cvId,
      candidateOwnerId: candidateOwnerId,
      snapshot: candidateSnapshot,
    );
    final uri = _uri('/candidates/resolve-canonical');
    final headers = await _headers();
    final payload = <String, dynamic>{
      'rawCandidateId': rawCandidateId.trim(),
      'cvId': cvId.trim(),
      'candidateOwnerId': candidateOwnerId.trim(),
      'ids': lookupIds,
    };
    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] POST $uri resolve-canonical body=$payload',
      );
    }
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    await _throwIfFailed(response, uri: uri);
    final json = _decodeObject(response.body);
    final canonical = CandidateIdentityResolver.normalizeCanonicalCandidateId(
      json['candidate_id'],
    );
    final matchedBy = (json['matchedBy'] ?? '').toString().trim();
    return CandidateCanonicalResolveResult(
      canonicalCandidateId: canonical,
      matchedBy: matchedBy,
    );
  }

  Future<Set<String>> getUnlockedCandidateIds() async {
    final uri = _uri('/employer/contacts/unlocked');
    final isGuestSurface = _shouldUseGuestContactEmployerHeaders();
    try {
      final headers = isGuestSurface
          ? await _guestContactHeaders(json: false)
          : await _headers(json: false);
      if (kDebugMode) {
        debugPrint(
          '[PaymentsRepository] GET $uri scope=${isGuestSurface ? 'guest' : 'auth'}',
        );
      }
      RuntimeFlowLogger.mark('CONTACT_UNLOCKS_FETCH_START', <String, Object?>{
        'url': uri.toString(),
        'ownerScope': isGuestSurface ? 'guest' : 'auth',
        'guestSessionId': isGuestSurface ? _guestSessionId() : '',
      });
      final response = await _client.get(uri, headers: headers);
      if (response.statusCode == 401 || response.statusCode == 403) {
        RuntimeFlowLogger.mark('CONTACT_UNLOCKS_FETCH_DENIED', <String, Object?>{
          'url': uri.toString(),
          'status': response.statusCode,
          'ownerScope': isGuestSurface ? 'guest' : 'auth',
          'guestSessionId': isGuestSurface ? _guestSessionId() : '',
          'body': response.body,
        });
        if (kDebugMode) {
          debugPrint(
            '[PaymentsRepository] GET $uri unauthorized (${response.statusCode}); returning empty unlocked set',
          );
        }
        return <String>{};
      }
      await _throwIfFailed(response, uri: uri);
      final root = _decodeObject(response.body);
      final raw = (root['candidateIds'] is List)
          ? root['candidateIds'] as List
          : const [];
      final ids = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      RuntimeFlowLogger.mark('CONTACT_UNLOCKS_FETCH_OK', <String, Object?>{
        'url': uri.toString(),
        'ownerScope': isGuestSurface ? 'guest' : 'auth',
        'guestSessionId': isGuestSurface ? _guestSessionId() : '',
        'count': ids.length,
      });
      return ids;
    } catch (e) {
      RuntimeFlowLogger.mark('CONTACT_UNLOCKS_FETCH_FAILED', <String, Object?>{
        'url': uri.toString(),
        'ownerScope': isGuestSurface ? 'guest' : 'auth',
        'guestSessionId': isGuestSurface ? _guestSessionId() : '',
        'error': e.toString(),
      });
      if (kDebugMode) {
        debugPrint(
          '[PaymentsRepository] GET $uri failed; returning empty unlocked set: $e',
        );
      }
      return <String>{};
    }
  }

  Future<VerificationStatusResult> getVerificationStatus() async {
    final uri = _uri('/employer/verification/status');
    final headers = await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    return VerificationStatusResult.fromJson(_decodeObject(response.body));
  }

  Future<void> uploadVerificationFile({
    required File file,
    String notes = '',
  }) async {
    final token = await _authToken();
    final request = http.MultipartRequest(
      'POST',
      _uri('/employer/verification/upload'),
    );
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    request.fields['notes'] = notes;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    await _throwIfFailed(response, uri: _uri('/employer/verification/upload'));
  }

  Future<PaymentTariffsResponse> fetchTariffs() async {
    final uri = _uri('/payments/tariffs');
    RuntimeFlowLogger.mark('TARIFFS_FETCH_START', <String, Object?>{
      'url': uri.toString(),
    });
    try {
      if (kDebugMode) {
        debugPrint(
          '[API_FETCH_START] method=GET uri=$uri kind=payments_tariffs',
        );
      }
      User? authUser;
      if (_isGuestCheckoutModeForContact()) {
        authUser = FirebaseAuth.instance.currentUser;
        RuntimeFlowLogger.mark('TARIFFS_FETCH_AUTH_READY', <String, Object?>{
          'url': uri.toString(),
          'uid': authUser?.uid ?? '',
          'guest': true,
        });
      } else {
        authUser = await _requireSignedInUser(reason: 'payments tariffs');
        RuntimeFlowLogger.mark('TARIFFS_FETCH_AUTH_READY', <String, Object?>{
          'url': uri.toString(),
          'uid': authUser.uid,
        });
      }
      final headers = _isGuestCheckoutModeForContact()
          ? await _guestContactHeaders(json: false)
          : await _headers(json: false);
      if (kDebugMode) {
        debugPrint('[PaymentsRepository] GET $uri');
      }
      final response = await _client.get(uri, headers: headers);
      await _throwIfFailed(response, uri: uri);
      final data = _decodeObject(response.body);
      final prices = <String, int>{};
      final tariffsNode = data['tariffs'];
      if (tariffsNode is Map) {
        tariffsNode.forEach((key, value) {
          final feature = key.toString().trim();
          if (feature.isEmpty) return;
          if (value is Map) {
            final dynamic amount = value['amount'] ?? value['amountCents'];
            final cents = amount is num
                ? amount.toInt()
                : int.tryParse('$amount');
            if (cents != null) prices[feature] = cents;
            return;
          }
          final cents = value is num ? value.toInt() : int.tryParse('$value');
          if (cents != null) prices[feature] = cents;
        });
      }
      return PaymentTariffsResponse(prices);
    } catch (e) {
      RuntimeFlowLogger.mark('TARIFFS_FETCH_FAILED', <String, Object?>{
        'url': uri.toString(),
        'error': e.toString(),
      });
      if (kDebugMode) {
        debugPrint('[API_FETCH_ERROR] method=GET uri=$uri error=$e');
        debugPrint('[PaymentsRepository] fetchTariffs failed: $e');
      }
      return PaymentTariffsResponse.empty();
    }
  }
}

class PaymentTariffsResponse {
  PaymentTariffsResponse(this.prices);

  /// key: feature/product id, value: amount in cents
  final Map<String, int> prices;

  factory PaymentTariffsResponse.empty() => PaymentTariffsResponse(const {});
}
