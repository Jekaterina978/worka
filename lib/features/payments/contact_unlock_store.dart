import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactUnlockStore {
  ContactUnlockStore._();

  static final ContactUnlockStore instance = ContactUnlockStore._();

  static const String _keyPrefix = 'opened_contacts_v1_';

  final Set<String> _openedCandidateIds = <String>{};
  String _scope = 'guest';
  bool _loaded = false;

  bool isOpened(String candidateId) {
    // NOTE: local UX-cache only.
    // Authoritative access lives on server in
    // employers/{employerId}/contact_unlocks/{candidateId}.
    final id = candidateId.trim();
    if (id.isEmpty) return false;
    return _openedCandidateIds.contains(id);
  }

  Set<String> openedIdsSnapshot() {
    return Set<String>.from(_openedCandidateIds);
  }

  Future<void> load({String? uid}) async {
    final nextScope = _normalizeScope(uid);
    if (_loaded && _scope == nextScope) return;
    _scope = nextScope;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('$_keyPrefix$_scope') ?? const <String>[];
    _openedCandidateIds
      ..clear()
      ..addAll(list.map((e) => e.trim()).where((e) => e.isNotEmpty));
    _loaded = true;
  }

  Future<void> markOpened(String candidateId, {String? uid}) async {
    final id = candidateId.trim();
    if (id.isEmpty) return;
    await load(uid: uid);
    if (_openedCandidateIds.add(id)) {
      await _save();
    }
  }

  Future<void> replaceOpenedIds(
    Iterable<String> candidateIds, {
    String? uid,
  }) async {
    await load(uid: uid);
    final normalized = candidateIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (setEquals(_openedCandidateIds, normalized)) {
      return;
    }
    _openedCandidateIds
      ..clear()
      ..addAll(normalized);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_keyPrefix$_scope',
      _openedCandidateIds.toList(),
    );
  }

  String _normalizeScope(String? uid) {
    final u = (uid ?? '').trim();
    return u.isEmpty ? 'guest' : u;
  }
}
