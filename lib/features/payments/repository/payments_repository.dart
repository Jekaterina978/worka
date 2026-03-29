// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:worka/core/platform/web_origin.dart';

import '../domain/models/credits_models.dart';
import '../models/checkout_session_status.dart';
import '../models/employer_payment_models.dart';
import '../models/payment_intent_response.dart';
import '../models/vacancy_payment_feature.dart';
import 'package:worka/models/job_entitlements.dart';

class PaymentsRepository {
  PaymentsRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _kAuthRestoreTimeout = Duration(seconds: 8);

  String get _baseUrl {
    const paymentsEnv = String.fromEnvironment('PAYMENTS_API_BASE_URL');
    const workaEnv = String.fromEnvironment('WORKA_API_BASE_URL');
    // Prefer explicit payments base, otherwise fall back to main API base.
    final raw = paymentsEnv.trim().isNotEmpty ? paymentsEnv : workaEnv;
    if (raw.trim().isEmpty) {
      if (kReleaseMode) {
        throw StateError(
          'PAYMENTS_API_BASE_URL or WORKA_API_BASE_URL must be set via --dart-define',
        );
      }
      // Dev fallback: local backend server (same as other REST endpoints in the app).
      // Override via --dart-define=WORKA_API_BASE_URL=<url> in launch.json.
      const devFallback = 'http://localhost:3000';
      print(
        '[PaymentsRepository] WARNING: no API base URL configured; '
        'falling back to local dev server $devFallback/api. '
        'Set WORKA_API_BASE_URL via --dart-define to suppress.',
      );
      print('[PaymentsRepository] resolvedBaseUrl=$devFallback/api');
      return '$devFallback/api';
    }
    final normalized = raw.trim().replaceAll(RegExp(r'/+$'), '');
    final resolved = normalized.endsWith('/api') ? normalized : '$normalized/api';
    print('[PaymentsRepository] resolvedBaseUrl=$resolved');
    return resolved;
  }

  Future<User> _requireSignedInUser({required String reason}) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentsRepository] waiting for FirebaseAuth restore before $reason',
        );
      }
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((candidate) => candidate != null)
            .timeout(_kAuthRestoreTimeout);
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }
    }

    if (user == null) {
      throw StateError(
        'User session is required for $reason, but auth was not restored in time.',
      );
    }
    if (user.isAnonymous) {
      throw StateError(
        'Anonymous session is not allowed for $reason. Please sign in.',
      );
    }
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

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _authToken();
    return <String, String>{
      if (json) HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $token',
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
    try {
      final headers = await _headers(json: false);
      if (kDebugMode) {
        debugPrint('[PaymentsRepository] GET $uri');
      }
      final response = await _client.get(uri, headers: headers);
      if (response.statusCode == 404) {
        if (kDebugMode) {
          debugPrint(
            '[PaymentsRepository] GET $uri -> 404; returning empty wallet',
          );
        }
        return EmployerWallet(
          uid: fallbackUid,
          balance: 0,
          unlockedCandidateIds: const {},
          fetchedAt: DateTime.now(),
        );
      }
      await _throwIfFailed(response, uri: uri);
      final json = _decodeObject(response.body);
      final uid = (json['uid'] ?? fallbackUid).toString().trim();
      final rawCredits = json['credits'];
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
      return EmployerWallet(
        uid: uid,
        balance: credits,
        unlockedCandidateIds: rawIds
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet(),
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentsRepository] GET $uri failed; returning empty wallet: $e',
        );
      }
      return EmployerWallet(
        uid: fallbackUid,
        balance: 0,
        unlockedCandidateIds: const {},
        fetchedAt: DateTime.now(),
      );
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
    String? targetId,
    String? targetType,
  }) async {
    try {
      print('[PAYMENT DEBUG] START createCheckoutSessionUrl');
      print('[PAYMENT DEBUG] featureKey=$productId');
      print('[PAYMENT DEBUG] ownerType=$ownerType');
      print('[PAYMENT DEBUG] ownerId=${ownerId ?? ''}');
      print('[PAYMENT DEBUG] targetType=${targetType ?? ''}');
      print('[PAYMENT DEBUG] targetId=${targetId ?? ''}');
      print('[PAYMENT DEBUG] amountCents=$amountCents');
      final returnOrigin = getCurrentOrigin();
      if (returnOrigin.isNotEmpty) {
        print('[PAYMENT DEBUG] returnOrigin=$returnOrigin');
      }

      final restoredUser = await _requireSignedInUser(reason: 'checkout');
      final effectiveOwnerId = (ownerId ?? restoredUser.uid).trim();
      final effectiveTargetId = (targetId ?? effectiveOwnerId).trim();
      final effectiveTargetType =
          (targetType ?? ownerType).trim().isEmpty ? ownerType : targetType;
      if (effectiveOwnerId.isEmpty || effectiveTargetId.isEmpty) {
        print(
          '[PAYMENT DEBUG] ERROR blocked: missing owner/target '
          'ownerId=$effectiveOwnerId targetId=$effectiveTargetId featureKey=$productId',
        );
        throw StateError('Missing owner or target for checkout.');
      }

      final body = <String, dynamic>{
        'feature_key': productId,
        'productId': productId,
        'amount': amountCents / 100,
        'amount_cents': amountCents,
        'currency': currency,
        'owner_type': ownerType,
        'owner_id': effectiveOwnerId,
        'target_type': effectiveTargetType,
        'target_id': effectiveTargetId,
        'context': <String, dynamic>{'origin': 'checkout_generic'},
        if (returnOrigin.isNotEmpty) 'return_origin': returnOrigin,
        if (effectiveTargetType == 'candidate')
          'return_context': {
            'mode': 'direct_unlock',
            'candidate_id': effectiveTargetId,
          },
      };
      final uri = _uri('/payments/checkout');

      print('[PAYMENT DEBUG] baseUrl=$_baseUrl');
      print('[PAYMENT DEBUG] endpoint=/payments/checkout');
      print('[PAYMENT DEBUG] body=${jsonEncode(body)}');

      final headers = await _headers();

      final response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      print('[PAYMENT DEBUG] status=${response.statusCode}');
      print('[PAYMENT DEBUG] response=${response.body}');

      await _throwIfFailed(response, uri: uri);
      final data = _decodeObject(response.body);
      final url = (data['url'] ?? '').toString().trim();
      if (url.isEmpty) {
        print('[PAYMENT DEBUG] ERROR missing url in response body=${response.body}');
        throw StateError('Missing checkout url in response.');
      }

      print('[PAYMENT DEBUG] checkoutUrl=$url');
      return url;
    } catch (e) {
      print('[PAYMENT DEBUG] ERROR=$e');
      rethrow;
    }
  }

  Future<String> createVacancyCheckoutSessionUrl({
    required String canonicalProductId,
    required String jobId,
    Map<String, dynamic>? context,
    String? returnOrigin,
    String? sourceScreen,
  }) async {
    final user = await _requireSignedInUser(reason: 'vacancy checkout');
    final spec = VacancyPaymentFeatures.byAnyId(canonicalProductId);
    if (spec == null) {
      throw StateError(
        'Unsupported vacancy product for checkout: $canonicalProductId',
      );
    }
    final trimmedJobId = jobId.trim();
    final amountCents = spec.paymentProduct.cents;
    final resolvedOrigin =
        (returnOrigin != null && returnOrigin.trim().isNotEmpty)
            ? returnOrigin.trim()
            : getCurrentOrigin();
    print(
      '[PAYMENT DEBUG] vacancy returnOrigin=$resolvedOrigin targetId=$trimmedJobId featureKey=${spec.backendProductId}',
    );
    debugPrint(
      '[PAYMENT] start featureKey=${spec.backendProductId} ownerType=employer '
      'ownerId=${user.uid} targetType=job targetId=$trimmedJobId amountCents=$amountCents',
    );
    if (trimmedJobId.isEmpty) {
      throw StateError('Missing jobCode for vacancy checkout.');
    }
    final uri = _uri('/payments/checkout');
    final headers = await _headers();
    final body = <String, dynamic>{
      'feature_key': spec.backendProductId,
      'productId': spec.backendProductId,
      'canonicalProductId': spec.canonicalId,
      'amount': amountCents / 100,
      'amount_cents': amountCents,
      'currency': 'EUR',
      'owner_type': 'employer',
      'owner_id': user.uid,
      'target_type': 'job',
      'target_id': trimmedJobId,
      'context': <String, dynamic>{'jobId': trimmedJobId, ...?context},
      if (resolvedOrigin.isNotEmpty) 'return_origin': resolvedOrigin,
      'returnContext': <String, dynamic>{
        'origin': (returnOrigin ?? '').trim(),
        'jobId': trimmedJobId,
        'product': spec.canonicalId,
        'sourceScreen': (sourceScreen ?? '').trim(),
      },
    };

    if (kDebugMode) {
      debugPrint(
        '[PaymentsRepository] vacancy checkout begin canonicalProductId=${spec.canonicalId} backendProductId=${spec.backendProductId} jobId=$trimmedJobId',
      );
      debugPrint('[PaymentsRepository] POST $uri');
    }

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    await _throwIfFailed(response, uri: uri);
    final data = _decodeObject(response.body);
    final url = (data['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw StateError('Missing checkout url in vacancy checkout response.');
    }
    return url;
  }

  Future<CheckoutSessionStatus> getCheckoutSessionStatus({
    required String sessionId,
  }) async {
    final uri = _uri('/payments/checkout-session-status');
    final headers = await _headers();
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(<String, dynamic>{'sessionId': sessionId.trim()}),
    );
    await _throwIfFailed(response, uri: uri);
    return CheckoutSessionStatus.fromJson(_decodeObject(response.body));
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
    final headers = await _headers(json: false);
    if (kDebugMode) {
      debugPrint('[PaymentsRepository] GET $uri');
    }
    final response = await _client.get(uri, headers: headers);
    await _throwIfFailed(response, uri: uri);
    return CandidateContact.fromJson(_decodeObject(response.body));
  }

  Future<Set<String>> getUnlockedCandidateIds() async {
    final uri = _uri('/employer/contacts/unlocked');
    try {
      final headers = await _headers(json: false);
      if (kDebugMode) {
        debugPrint('[PaymentsRepository] GET $uri');
      }
      final response = await _client.get(uri, headers: headers);
      if (response.statusCode == 401 || response.statusCode == 403) {
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
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (e) {
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
}
