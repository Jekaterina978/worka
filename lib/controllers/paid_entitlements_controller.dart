import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Minimal reactive store for paid entitlements (CV and Job).
/// Singleton for now; can be provided at app root.
class PaidEntitlementsController extends ChangeNotifier {
  PaidEntitlementsController._();
  static final PaidEntitlementsController instance =
      PaidEntitlementsController._();

  /// cvId -> set of features (e.g., {"highlight","priority","bump"})
  final Map<String, Set<String>> cvEntitlementsById = {};

  /// jobId -> set of features (e.g., {"highlight","urgent","bump","show_contacts"})
  final Map<String, Set<String>> jobEntitlementsById = {};

  static const _baseEnv = String.fromEnvironment(
    'WORKA_API_BASE_URL',
    defaultValue: '',
  );

  Future<void> refreshCvEntitlements(String cvId) async {
    final id = cvId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse('${_normalizedBase()}/api/cv/$id/entitlements');
      final headers = await _authHeaders();
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint(
          '[PAID_ENTITLE] cv fetch failed code=${resp.statusCode} body=${resp.body}',
        );
        return;
      }
      final data = jsonDecode(resp.body);
      final list = (data['entitlements'] as List?) ?? const [];
      cvEntitlementsById[id] = list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[PAID_ENTITLE] cv fetch error $e');
    }
  }

  Future<void> refreshJobEntitlements(String jobId) async {
    final id = jobId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse('${_normalizedBase()}/api/jobs/$id/entitlements');
      final headers = await _authHeaders();
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint(
          '[PAID_ENTITLE] job fetch failed code=${resp.statusCode} body=${resp.body}',
        );
        return;
      }
      final data = jsonDecode(resp.body);
      final list = (data['entitlements'] as List?) ?? const [];
      jobEntitlementsById[id] = list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[PAID_ENTITLE] job fetch error $e');
    }
  }

  bool hasCvFeature(String cvId, String feature) {
    final set = cvEntitlementsById[cvId.trim()];
    if (set == null) return false;
    return set.contains(feature.trim());
  }

  bool hasJobFeature(String jobId, String feature) {
    final set = jobEntitlementsById[jobId.trim()];
    if (set == null) return false;
    return set.contains(feature.trim());
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String _normalizedBase() {
    final b = _baseEnv.trim();
    if (b.isEmpty) {
      throw StateError('WORKA_API_BASE_URL is required for entitlements fetch');
    }
    return b.endsWith('/api') ? b : '$b/api';
  }
}
