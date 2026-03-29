import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:worka/config/app_env.dart';
import 'package:worka/firebase_options.dart';

/// Calls the backend AI endpoints:
///   POST /ai/parse-vacancy
///   POST /ai/parse-cv
///   POST /ai/parse-vacancy-url
///
/// Mirrors the HTTP pattern used by [PaymentsRepository].
/// All calls are authenticated with Firebase ID token.
class AiParserService {
  AiParserService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl {
    const aiCustom = String.fromEnvironment('AI_API_BASE_URL');
    const legacyCustom = String.fromEnvironment('PAYMENTS_API_BASE_URL');
    final custom = aiCustom.trim().isNotEmpty ? aiCustom : legacyCustom;
    assert(custom.trim().isNotEmpty, 'AI_API_BASE_URL or PAYMENTS_API_BASE_URL is required');
    return _normalizeApiBase(custom.trim());
  }

  String _normalizeApiBase(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    final noTrailing = trimmed.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(noTrailing);
    if (uri == null) return noTrailing;

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path == '/api' || path.endsWith('/api')) {
      return noTrailing;
    }
    if (path.isEmpty || path == '/') {
      return '$noTrailing/api';
    }
    return noTrailing;
  }

  Future<String> _authToken() async {
    User? user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) throw StateError('User session required for AI parser.');
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Failed to get Firebase ID token.');
    }
    if (kDebugMode) {
      debugPrint(
        '[AiParserService] auth token ready uid=${user.uid} anon=${user.isAnonymous}',
      );
    }
    return token;
  }

  Future<Map<String, String>> _headers() async {
    final token = await _authToken();
    return {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  Future<Map<String, dynamic>> _post(String path, String text) async {
    final uri = _uri(path);
    final headers = await _headers();
    if (kDebugMode) debugPrint('[AiParserService] POST $uri');

    late final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'text': text}),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AiParserService] network failure url=$uri type=${e.runtimeType} error=$e',
        );
      }
      rethrow;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint(
          '[AiParserService] non-2xx url=$uri status=${response.statusCode} body=${response.body}',
        );
      }
      String msg = 'AI parse request failed (${response.statusCode})';
      try {
        final json = _decodeObject(response.body);
        final err = (json['error'] ?? '').toString().trim();
        if (err.isNotEmpty) msg = err;
      } catch (_) {}
      throw StateError(msg);
    }

    final root = _decodeObject(response.body);
    final parsed = root['parsed_data'];
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return {};
  }

  /// Parse raw vacancy/job posting text.
  /// Returns a map matching the vacancy form fields.
  Future<Map<String, dynamic>> parseVacancy(String text) =>
      _post('/ai/parse-vacancy', text);

  /// Parse raw CV/resume text.
  /// Returns a map matching the CV form fields.
  Future<Map<String, dynamic>> parseCv(String text) =>
      _post('/ai/parse-cv', text);

  /// Fetch a vacancy page by URL and parse it with AI.
  /// Returns a map matching the vacancy form fields.
  Future<Map<String, dynamic>> parseVacancyFromUrl(String url) async {
    final uri = _uri('/ai/parse-vacancy-url');
    final headers = await _headers();
    if (kDebugMode) debugPrint('[AiParserService] POST $uri (url=$url)');

    late final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'url': url}),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AiParserService] network failure url=$uri type=${e.runtimeType} error=$e',
        );
      }
      rethrow;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint(
          '[AiParserService] non-2xx url=$uri status=${response.statusCode} body=${response.body}',
        );
      }
      String msg =
          'Не удалось получить данные по ссылке (${response.statusCode})';
      try {
        final json = _decodeObject(response.body);
        final err = (json['error'] ?? '').toString().trim();
        if (err.isNotEmpty) msg = err;
      } catch (_) {}
      throw StateError(msg);
    }

    final root = _decodeObject(response.body);
    final parsed = root['parsed_data'];
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return {};
  }
}
