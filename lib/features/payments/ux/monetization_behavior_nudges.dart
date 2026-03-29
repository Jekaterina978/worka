import 'package:shared_preferences/shared_preferences.dart';

class MonetizationBehaviorNudges {
  MonetizationBehaviorNudges._();

  static final MonetizationBehaviorNudges instance =
      MonetizationBehaviorNudges._();

  static const int _viewsThreshold = 3;
  static const Duration _cooldown = Duration(hours: 8);

  String _uid = 'guest';
  SharedPreferences? _prefs;
  Set<String> _viewedWithoutUnlock = <String>{};
  int _lastViewedNudgeMs = 0;
  int _lastIncomingNudgeMs = 0;

  String _kViewedIds(String uid) => 'mon_nudge_viewed_ids_$uid';
  String _kViewedShownAt(String uid) => 'mon_nudge_viewed_shown_at_$uid';
  String _kIncomingShownAt(String uid) => 'mon_nudge_incoming_shown_at_$uid';

  Future<void> bootstrap({required String uid}) async {
    final cleanUid = uid.trim().isEmpty ? 'guest' : uid.trim();
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    if (_uid == cleanUid && _viewedWithoutUnlock.isNotEmpty) return;
    _uid = cleanUid;
    _viewedWithoutUnlock =
        (prefs.getStringList(_kViewedIds(_uid)) ?? const <String>[]).toSet();
    _lastViewedNudgeMs = prefs.getInt(_kViewedShownAt(_uid)) ?? 0;
    _lastIncomingNudgeMs = prefs.getInt(_kIncomingShownAt(_uid)) ?? 0;
  }

  Future<void> registerViewedWithoutUnlock(String candidateId) async {
    final id = candidateId.trim();
    if (id.isEmpty) return;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    _viewedWithoutUnlock.add(id);
    await prefs.setStringList(_kViewedIds(_uid), _viewedWithoutUnlock.toList());
  }

  bool get shouldShowViewedContactsNudge {
    if (_viewedWithoutUnlock.length <= _viewsThreshold) return false;
    return _cooldownPassed(_lastViewedNudgeMs);
  }

  bool get shouldShowIncomingInteractionNudge {
    return _cooldownPassed(_lastIncomingNudgeMs);
  }

  Future<void> markViewedNudgeShown() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastViewedNudgeMs = now;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setInt(_kViewedShownAt(_uid), now);
  }

  Future<void> markIncomingNudgeShown() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastIncomingNudgeMs = now;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setInt(_kIncomingShownAt(_uid), now);
  }

  bool _cooldownPassed(int lastShownMs) {
    if (lastShownMs <= 0) return true;
    final diff = DateTime.now().millisecondsSinceEpoch - lastShownMs;
    return diff >= _cooldown.inMilliseconds;
  }
}
