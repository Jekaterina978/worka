import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:worka/features/monetization/pricing.dart';

class WorkerEntitlements {
  final int activeCvLimit;
  final bool workerPlus;
  final int boostsPerWeek;
  final DateTime? highlightActiveUntil;
  final DateTime? priorityActiveUntil;
  final bool verified;

  const WorkerEntitlements({
    required this.activeCvLimit,
    required this.workerPlus,
    required this.boostsPerWeek,
    required this.highlightActiveUntil,
    required this.priorityActiveUntil,
    required this.verified,
  });

  factory WorkerEntitlements.free() {
    return const WorkerEntitlements(
      activeCvLimit: MonetizationPricing.workerFreeActiveCvLimit,
      workerPlus: false,
      boostsPerWeek: 0,
      highlightActiveUntil: null,
      priorityActiveUntil: null,
      verified: false,
    );
  }
}

class WorkerEntitlementsRepository {
  WorkerEntitlementsRepository(this._db);

  final FirebaseFirestore _db;
  final _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  WorkerEntitlements _fromDoc(Map<String, dynamic> data) {
    final worker = data['worker'] is Map
        ? Map<String, dynamic>.from(data['worker'] as Map)
        : const <String, dynamic>{};

    final planRaw = (worker['plan'] ?? data['workerPlan'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final workerPlus = planRaw == 'worker_plus';

    final freeLimit = MonetizationPricing.workerFreeActiveCvLimit;
    int limit = freeLimit;
    final rawLimit = worker['activeCvLimit'] ?? data['activeCvLimit'];
    if (rawLimit is int && rawLimit > 0) {
      limit = rawLimit < freeLimit ? freeLimit : rawLimit;
    } else if (workerPlus) {
      limit = freeLimit + MonetizationPricing.workerPlusExtraCv;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String && raw.trim().isNotEmpty) {
        return DateTime.tryParse(raw.trim());
      }
      return null;
    }

    return WorkerEntitlements(
      activeCvLimit: limit,
      workerPlus: workerPlus,
      boostsPerWeek: (worker['boostsPerWeek'] is int)
          ? worker['boostsPerWeek'] as int
          : (workerPlus ? 1 : 0),
      highlightActiveUntil: parseDate(worker['highlightActiveUntil']),
      priorityActiveUntil: parseDate(worker['priorityActiveUntil']),
      verified: (worker['verified'] == true) || (data['verified'] == true),
    );
  }

  Stream<WorkerEntitlements> watch(String uid) {
    return _userRef(uid).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return _fromDoc(data);
    });
  }

  Future<WorkerEntitlements> get(String uid) async {
    final snap = await _userRef(uid).get();
    return _fromDoc(snap.data() ?? const <String, dynamic>{});
  }

  Future<void> applyPurchase({
    required String uid,
    required String productId,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для применения покупки.');
    }
    final base = const String.fromEnvironment(
      'WORKA_API_BASE_URL',
      defaultValue: '',
    );
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = Uri.parse('$normalizedBase/worker/entitlements');
    final body = {
      'userId': uid,
      'productId': productId,
      'source': 'worker_entitlements_repository',
    };
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final text = resp.body.trim();
      throw StateError(
        'Не удалось применить покупку: '
        '${text.isNotEmpty ? text : 'status=${resp.statusCode}'}',
      );
    }
  }
}
