import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/widgets/cards/candidate_list_card.dart';
import 'package:worka/widgets/candidate_offer_sent_badge.dart';

import 'package:worka/screens/search/widgets/location_picker_sheet.dart';

import 'package:worka/screens/employer/search/models/candidate_filters.dart';
import 'package:worka/screens/employer/search/models/candidate_filters_config.dart';
import 'package:worka/screens/employer/search/widgets/candidate_filters_screen.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_sheet.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';
import 'package:worka/features/payments/ux/monetization_behavior_nudges.dart';
import 'package:worka/features/payments/usecases/unlock_candidate_contact_use_case.dart';

import 'package:worka/services/favorites_bus.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/public_cv_sanitizer.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/widgets/burger_drawer.dart';
import 'package:worka/widgets/profile_avatar_button.dart';

class CandidateSearchScreen extends StatefulWidget {
  const CandidateSearchScreen({super.key});

  @override
  State<CandidateSearchScreen> createState() => _CandidateSearchScreenState();
}

class _CandidateSearchScreenState extends State<CandidateSearchScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _contactAccess = ContactAccessController.instance;
  final _unlockCandidateContact = UnlockCandidateContactUseCase();
  final _nudges = MonetizationBehaviorNudges.instance;

  final _qCtrl = TextEditingController();
  final _qFocus = FocusNode();

  CandidateFilters _filters = CandidateFilters.initial();

  static const double fieldH = 56;
  static const double btnH = 56;
  static const double radius = 18;

  bool _showSuggest = false;

  late final List<String> _keywordPool = CandidateFiltersConfig.keywordPool();

  /// ✅ ВАЖНО: CandidateFiltersConfig.allCountries() у тебя НЕ существует.
  /// Чтобы проект запускался, оставляем пусто.
  /// LocationPickerSheet сам покажет страны (fallback внутри него).
  static const List<String> _allCountries = <String>[];

  // ===== избранное кандидатов =====
  static const _prefsKeyCand = 'worka_favorites_candidate_ids';
  Set<String> _localFav = {};
  Set<String> _remoteFav = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  StreamSubscription<void>? _favoritesBusSub;
  final Map<String, CandidateContact> _openedContacts =
      <String, CandidateContact>{};
  bool _showViewedContactsNudge = false;
  bool _showIncomingInteractionNudge = false;

  @override
  void initState() {
    super.initState();

    _loadLocalFav();
    _listenRemoteFav();
    _loadOpenedContacts();
    _initNudges();
    _listenIncomingInteractions();
    _favoritesBusSub = FavoritesBus.stream.listen((_) {
      _reloadFavoritesState();
    });

    _qFocus.addListener(() {
      if (!_qFocus.hasFocus) setState(() => _showSuggest = false);
    });

    _qCtrl.addListener(() {
      final t = _qCtrl.text.trim();
      setState(() => _showSuggest = t.isNotEmpty && _qFocus.hasFocus);
    });
  }

  Future<void> _loadOpenedContacts() async {
    await _contactAccess.bootstrap(uid: _auth.currentUser?.uid);
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _remoteFavSub?.cancel();
    _incomingSub?.cancel();
    _favoritesBusSub?.cancel();
    _qCtrl.dispose();
    _qFocus.dispose();
    super.dispose();
  }

  void _listenRemoteFav() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _remoteFavSub?.cancel();
    _remoteFavSub = _db
        .collection('users')
        .doc(uid)
        .collection('favoritesCandidates')
        .snapshots()
        .listen((snap) {
          final ids = <String>{};
          for (final d in snap.docs) {
            ids.add(d.id);
          }
          if (!mounted) return;
          setState(() => _remoteFav = ids);
        });
  }

  Future<void> _loadLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKeyCand) ?? const <String>[];
    if (!mounted) return;
    setState(() => _localFav = list.toSet());
  }

  Future<void> _reloadFavoritesState() async {
    await _loadLocalFav();
    _listenRemoteFav();
  }

  Future<void> _initNudges() async {
    await _nudges.bootstrap(uid: _auth.currentUser?.uid ?? 'guest');
    if (!mounted) return;
    setState(() {
      _showViewedContactsNudge = _nudges.shouldShowViewedContactsNudge;
    });
  }

  void _listenIncomingInteractions() {
    final uid = (_auth.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return;
    _incomingSub?.cancel();
    _incomingSub = _db
        .collection(FirestorePaths.applications)
        .where('employerOwnerId', isEqualTo: uid)
        .where('status', whereIn: const ['sent', 'viewed'])
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _showIncomingInteractionNudge =
                snap.docs.isNotEmpty &&
                _nudges.shouldShowIncomingInteractionNudge;
          });
        });
  }

  Future<void> _onViewedWithoutUnlock(String candidateId) async {
    await _nudges.registerViewedWithoutUnlock(candidateId);
    if (!mounted) return;
    setState(() {
      _showViewedContactsNudge = _nudges.shouldShowViewedContactsNudge;
    });
  }

  Future<void> _openNudgePaywall({
    required String entryPoint,
    required Future<void> Function() markShown,
  }) async {
    await markShown();
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await ContactUnlockPaywallSheet.open(
      context,
      entryPoint: entryPoint,
      mode: PaywallMode.creditsOnly,
    );
  }

  Future<void> _dismissViewedContactsNudge() async {
    await _nudges.markViewedNudgeShown();
    if (!mounted) return;
    setState(() => _showViewedContactsNudge = false);
  }

  Future<void> _dismissIncomingNudge() async {
    await _nudges.markIncomingNudgeShown();
    if (!mounted) return;
    setState(() => _showIncomingInteractionNudge = false);
  }

  Widget _nudgeBanner({
    required String text,
    required String entryPoint,
    required Future<void> Function() onDismiss,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WorkaColors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: WorkaColors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                _openNudgePaywall(entryPoint: entryPoint, markShown: onDismiss),
            child: const Text(
              'Открыть контакты',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: WorkaColors.textGreyDark,
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }

  Future<void> _saveLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKeyCand, _localFav.toList());
  }

  bool _isFav(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _localFav.contains(id);
    // When logged in, remote is the source of truth; local is only for guests.
    return _remoteFav.contains(id);
  }

  Future<void> _toggleFav(String candidateId, Map<String, dynamic> data) async {
    final uid = _auth.currentUser?.uid;
    final nowFav = !_isFav(candidateId);

    if (uid != null) {
      // Optimistic update on the remote set so the star flips instantly.
      setState(() {
        if (nowFav) {
          _remoteFav.add(candidateId);
        } else {
          _remoteFav.remove(candidateId);
        }
      });
    } else {
      setState(() {
        if (nowFav) {
          _localFav.add(candidateId);
        } else {
          _localFav.remove(candidateId);
        }
      });
      await _saveLocalFav();
    }

    if (uid != null) {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('favoritesCandidates')
          .doc(candidateId);

      if (nowFav) {
        await ref.set({
          'candidateId': candidateId,
          'name': data['name'],
          'profession': data['profession'] ?? data['category'],
          'city': data['city'],
          'country': data['country'],
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.delete();
      }
    }

    FavoritesBus.notify();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _candidatesStream() {
    debugPrint('CandidateSearchScreen query=cvs orderBy createdAt desc');
    return _db
        .collection(FirestorePaths.cvs)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) {
          final docs = [...s.docs];
          DateTime parseDate(dynamic v) => v is Timestamp
              ? v.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          docs.sort((a, b) {
            final au = parseDate(a.data()['updatedAt']);
            final bu = parseDate(b.data()['updatedAt']);
            if (au != bu) return bu.compareTo(au);
            final ac = parseDate(a.data()['createdAt']);
            final bc = parseDate(b.data()['createdAt']);
            return bc.compareTo(ac);
          });
          final out = docs
              .where((d) => WorkaEntityValidity.isValidPublicCv(d.data()))
              .toList();
          debugPrint('CandidateSearchScreen result count=${out.length}');
          return out;
        });
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Map<String, dynamic> _contacts(Map<String, dynamic> m) =>
      (m['contacts'] is Map)
      ? Map<String, dynamic>.from(m['contacts'])
      : <String, dynamic>{};
  Map<String, dynamic> _desired(Map<String, dynamic> m) => (m['desired'] is Map)
      ? Map<String, dynamic>.from(m['desired'])
      : <String, dynamic>{};
  String _cvName(Map<String, dynamic> m) {
    final c = _contacts(m);
    final full = _s(c['name']);
    if (full.isNotEmpty) return full;
    final out = '${_s(c['firstName'])} ${_s(c['lastName'])}'.trim();
    return out.isEmpty ? 'Кандидат' : out;
  }

  String _cvProfession(Map<String, dynamic> m) {
    final d = _desired(m);
    return _s(
      d['position'],
      fallback: _s(d['categoryGroup'], fallback: _s(m['title'])),
    );
  }

  String _cvCountry(Map<String, dynamic> m) {
    final d = _desired(m);
    final countries = (d['countries'] is List)
        ? (d['countries'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    return countries.isEmpty ? '' : countries.first;
  }

  String _cvCity(Map<String, dynamic> m) {
    final d = _desired(m);
    final cities = _s(d['citiesText']);
    if (cities.isEmpty) return '';
    return cities.split(',').first.trim();
  }

  String _cvCategory(Map<String, dynamic> m) =>
      _s(_desired(m)['categoryGroup']);
  String _cvLanguages(Map<String, dynamic> m) {
    final list = (m['languages'] is List) ? (m['languages'] as List) : const [];
    return list
        .map((e) => (e is Map ? _s(e['language']) : ''))
        .where((e) => e.isNotEmpty)
        .join(' ');
  }

  String _cvAbout(Map<String, dynamic> m) => _s(m['summary']);

  // ===== keyword suggestions =====
  List<String> _suggestions(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final w in _keywordPool) {
      if (w.toLowerCase().contains(s)) out.add(w);
      if (out.length >= 10) break;
    }
    return out;
  }

  List<String> _tokenize(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return const [];
    return s
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _haystack(Map<String, dynamic> m) {
    final name = _cvName(m).toLowerCase();
    final profession = _cvProfession(m).toLowerCase();
    final about = _cvAbout(m).toLowerCase();
    final city = _cvCity(m).toLowerCase();
    final country = _cvCountry(m).toLowerCase();
    final langs = _cvLanguages(m).toLowerCase();

    return [name, profession, about, city, country, langs].join(' ');
  }

  bool _matchKeywords(Map<String, dynamic> m) {
    final tokens = _tokenize(_qCtrl.text);
    if (tokens.isEmpty) return true;

    final hay = _haystack(m);
    for (final w in tokens) {
      if (!hay.contains(w)) return false;
    }
    return true;
  }

  bool _matchLocation(Map<String, dynamic> m) {
    final cityLabel = (_filters.cityLabel ?? '').trim().toLowerCase();
    if (cityLabel.isNotEmpty) {
      final city = _cvCity(m).toLowerCase();
      final country = _cvCountry(m).toLowerCase();
      final label1 = '$city • $country';
      final label2 = '$city, $country';
      return label1.contains(cityLabel) ||
          label2.contains(cityLabel) ||
          city.contains(cityLabel) ||
          country.contains(cityLabel);
    }

    if (_filters.countries.isEmpty) return true;
    final c = _cvCountry(m);
    if (c.isEmpty) return true;
    return _filters.countries.contains(c);
  }

  bool _matchCategory(Map<String, dynamic> m) {
    if (_filters.categories.isEmpty) return true;
    final v = _cvProfession(m).isNotEmpty ? _cvProfession(m) : _cvCategory(m);
    if (v.isEmpty) return false;
    return _filters.categories.contains(v);
  }

  Set<String> _expandExperience(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return {};
    if (v == '1–2 года' || v == '1-2 года') return {'1 год', '2 года'};
    if (v == '3+ года' || v == '3+ лет') return {'3 года', '4+ года'};
    return {v};
  }

  bool _matchExperience(Map<String, dynamic> m) {
    if (_filters.experiences.isEmpty) return true;
    final raw = _s(m['experience']);
    if (raw.isEmpty) return false;
    final expanded = _expandExperience(raw);
    return expanded.any(_filters.experiences.contains);
  }

  bool _matchLanguages(Map<String, dynamic> m) {
    if (_filters.languages.isEmpty) return true;

    final l = m['languages'];
    final values = <String>[];

    if (l is List) {
      for (final x in l) {
        if (x is Map) {
          final map = Map<String, dynamic>.from(x);
          final language = _s(map['language'], fallback: _s(map['name']));
          if (language.isNotEmpty) values.add(language);
        } else {
          final s = _s(x);
          if (s.isNotEmpty) values.add(s);
        }
      }
    } else {
      final s = _s(l);
      if (s.isNotEmpty) {
        values.addAll(
          s
              .split(RegExp(r'[,;/]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty),
        );
      }
    }

    if (_filters.languages.contains('Без языка')) {
      if (values.isEmpty) return true;
    }
    if (values.isEmpty) return false;

    return values.any((v) => _filters.languages.contains(v));
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final m = d.data();
      if (!_matchKeywords(m)) continue;
      if (!_matchLocation(m)) continue;
      if (!_matchCategory(m)) continue;
      if (!_matchLanguages(m)) continue;
      if (!_matchExperience(m)) continue;
      out.add(d);
    }
    return out;
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  Future<void> _handleContactTap({
    required String candidateId,
    required String candidateName,
    required VoidCallback openDetails,
  }) async {
    await _showContactBottomSheet(
      candidateId: candidateId,
      candidateName: candidateName,
      openDetails: openDetails,
    );
  }

  Future<void> _showContactBottomSheet({
    required String candidateId,
    required String candidateName,
    required VoidCallback openDetails,
  }) async {
    if (!mounted) return;
    CandidateContact? contact =
        _openedContacts[candidateId] ??
        _contactAccess.contactForCandidate(candidateId);
    var unlocked = _contactAccess.hasAccessToCandidateContact(candidateId);
    if (unlocked && contact == null) {
      contact = await _contactAccess.ensureLoadedContactForCandidate(
        candidateId,
      );
      if (contact != null) {
        _openedContacts[candidateId] = contact;
      }
    }
    if (!mounted) return;
    var loading = false;
    var creditsLeft = _contactAccess.creditsBalance;

    String maskPhone(String value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 6) return '+371 *** **23';
      final prefix = '+${digits.substring(0, 3)}';
      final tail = digits.substring(digits.length - 2);
      return '$prefix *** **$tail';
    }

    String maskEmail(String value) {
      final trimmed = value.trim();
      if (!trimmed.contains('@')) return 'j***@gmail.com';
      final parts = trimmed.split('@');
      final local = parts.first.trim();
      final domain = parts.last.trim();
      if (local.isEmpty || domain.isEmpty) return 'j***@gmail.com';
      return '${local.substring(0, 1)}***@$domain';
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> unlock() async {
            if (loading || _contactAccess.isUnlockInProgress(candidateId)) {
              return;
            }
            setSheetState(() => loading = true);
            try {
              if (!context.mounted) return;
              final rootContext = Navigator.of(
                context,
                rootNavigator: true,
              ).context;
              final result = await _unlockCandidateContact(
                rootContext,
                candidateId: candidateId,
                candidateName: candidateName,
                entryPoint: 'candidate_search_bottom_sheet',
              );
              if (!result.isSuccess) {
                if (result.status == ContactUnlockStatus.purchasePending) {
                  final message = result.message.trim().isNotEmpty
                      ? result.message.trim()
                      : 'Платёж подтверждён, кредиты обновляются...';
                  _toast(message);
                } else if (result.status == ContactUnlockStatus.cancelled) {
                  _toast('Оплата отменена');
                } else {
                  final message = result.message.trim().isNotEmpty
                      ? result.message.trim()
                      : 'Не удалось открыть контакты';
                  _toast(message, error: true);
                }
                setSheetState(() => loading = false);
                return;
              }
              contact =
                  result.contact ??
                  await _contactAccess.ensureLoadedContactForCandidate(
                    candidateId,
                  ) ??
                  contact;
              if (contact != null) {
                _openedContacts[candidateId] = contact!;
              }
              creditsLeft = result.creditsLeft;
              unlocked = true;
              if (mounted) setState(() {});
            } catch (_) {
              _toast('Не удалось открыть контакты', error: true);
            } finally {
              setSheetState(() => loading = false);
            }
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: WorkaColors.fieldBorder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    unlocked ? 'Контакты открыты' : 'Контакты кандидата',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    candidateName.isEmpty ? 'Кандидат' : candidateName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Телефон: ${unlocked ? (contact?.phone.trim().isNotEmpty == true ? contact!.phone : '—') : maskPhone(contact?.phone ?? '')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Email: ${unlocked ? (contact?.email.trim().isNotEmpty == true ? contact!.email : '—') : maskEmail(contact?.email ?? '')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (unlocked) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Кредитов осталось: $creditsLeft',
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: loading
                              ? null
                              : () => Navigator.pop(sheetCtx),
                          child: const Text('Закрыть'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: loading
                              ? null
                              : (unlocked
                                    ? () {
                                        Navigator.pop(sheetCtx);
                                        openDetails();
                                      }
                                    : unlock),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  unlocked
                                      ? 'Открыть профиль'
                                      : 'Открыть контакты',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _locationLabel() {
    final city = (_filters.cityLabel ?? '').trim();
    if (city.isNotEmpty) return city;
    if (_filters.countries.isEmpty) return 'Где работать?';
    if (_filters.countries.length <= 2) return _filters.countries.join(', ');
    return 'Выбрано: ${_filters.countries.length}';
  }

  Future<void> _openLocationPicker() async {
    final res = await LocationPickerSheet.open(
      context,
      allCountries:
          _allCountries, // ✅ ок, даже если пусто — пикер покажет fallback страны
      initialCountries: _filters.countries,
      initialCityLabel: _filters.cityLabel,
      singleSelect: false,
      // cityToCountry: {...} // если подключим подсказки городов — прокинем сюда
    );

    if (res == null) return;

    setState(() {
      _filters = _filters.copyWith(
        countries: res.countries,
        cityLabel: res.pickedCityLabel,
        clearCityLabel: res.pickedCityLabel == null,
      );
    });
  }

  Future<void> _openFilters() async {
    final res = await Navigator.push<CandidateFilters>(
      context,
      MaterialPageRoute(
        builder: (_) => CandidateFiltersScreen(initial: _filters),
      ),
    );
    if (res == null) return;
    setState(() => _filters = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => BurgerDrawer.open(context),
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Поиск кандидатов',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const ProfileAvatarButton(),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        children: [
                          SizedBox(
                            height: fieldH,
                            child: TextField(
                              controller: _qCtrl,
                              focusNode: _qFocus,
                              style: const TextStyle(
                                color: WorkaColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Кем?',
                                hintStyle: const TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w800,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: WorkaColors.textGreyDark,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                  borderSide: const BorderSide(
                                    color: WorkaColors.fieldBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                  borderSide: const BorderSide(
                                    color: WorkaColors.blue,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          if (_showSuggest) ...[
                            const SizedBox(height: 8),
                            _SuggestBox(
                              items: _suggestions(_qCtrl.text),
                              onPick: (v) {
                                _qCtrl.text = v;
                                _qCtrl.selection = TextSelection.collapsed(
                                  offset: v.length,
                                );
                                setState(() => _showSuggest = false);
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ],

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _TapField(
                                  height: fieldH,
                                  label: _locationLabel(),
                                  hasValue: _locationLabel() != 'Где работать?',
                                  prefix: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  onTap: _openLocationPicker,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: btnH,
                                width: 120,
                                child: _FindGradientButton(
                                  onTap: () => setState(() {}),
                                  label: 'Найти',
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          SizedBox(
                            height: btnH,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openFilters,
                              icon: const Icon(Icons.tune, color: Colors.white),
                              label: const Text(
                                'Фильтры',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WorkaColors.orange,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child:
                          StreamBuilder<
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          >(
                            stream: _candidatesStream(),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Center(
                                  child: Text(
                                    'Ошибка: ${snap.error}',
                                    style: const TextStyle(
                                      color: WorkaColors.textGreyDark,
                                    ),
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }

                              final docs = snap.data!;
                              final filtered = _applyFilters(docs);

                              if (filtered.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: Text(
                                      'Ничего не найдено',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: WorkaColors.textGreyDark,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  if (_showViewedContactsNudge)
                                    _nudgeBanner(
                                      text: 'Свяжитесь с кандидатами напрямую',
                                      entryPoint:
                                          'candidate_search_viewed_nudge',
                                      onDismiss: _dismissViewedContactsNudge,
                                    ),
                                  if (_showIncomingInteractionNudge)
                                    _nudgeBanner(
                                      text:
                                          'Кандидат уже взаимодействует с вами',
                                      entryPoint:
                                          'candidate_search_incoming_nudge',
                                      onDismiss: _dismissIncomingNudge,
                                    ),
                                  Expanded(
                                    child: _CandidatesList(
                                      docs: filtered,
                                      isFav: _isFav,
                                      isContactOpened:
                                          _contactAccess.hasAccessToCandidate,
                                      onToggleFav: _toggleFav,
                                      onContactTap: _handleContactTap,
                                      onViewedWithoutUnlock:
                                          _onViewedWithoutUnlock,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= UI widgets (hoverSoft) =================

class _TapField extends StatelessWidget {
  final double height;
  final String label;
  final bool hasValue;
  final Widget? prefix;
  final VoidCallback onTap;

  const _TapField({
    required this.height,
    required this.label,
    required this.hasValue,
    this.prefix,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(_CandidateSearchScreenState.radius),
        onTap: onTap,
        hoverColor: WorkaColors.hoverBlueSoft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              _CandidateSearchScreenState.radius,
            ),
            border: Border.all(color: WorkaColors.fieldBorder),
          ),
          child: Row(
            children: [
              if (prefix != null) ...[
                IconTheme(
                  data: IconThemeData(color: Colors.grey.shade700),
                  child: prefix!,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: hasValue
                        ? WorkaColors.textDark
                        : WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                color: WorkaColors.textGreyDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindGradientButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const _FindGradientButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF5B8CFF), Color(0xFF2F5BFF)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F5BFF).withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          splashColor: Colors.black.withValues(alpha: 0.08),
          highlightColor: Colors.black.withValues(alpha: 0.10),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.02),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestBox extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onPick;

  const _SuggestBox({required this.items, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: WorkaColors.divider),
        itemBuilder: (context, i) {
          final v = items[i];
          return InkWell(
            onTap: () => onPick(v),
            hoverColor: WorkaColors.hoverBlueSoft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                v,
                style: const TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CandidatesList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool Function(String id) isFav;
  final bool Function(String candidateId) isContactOpened;
  final Future<void> Function(String id, Map<String, dynamic> data) onToggleFav;
  final Future<void> Function({
    required String candidateId,
    required String candidateName,
    required VoidCallback openDetails,
  })
  onContactTap;
  final Future<void> Function(String candidateId)? onViewedWithoutUnlock;

  const _CandidatesList({
    required this.docs,
    required this.isFav,
    required this.isContactOpened,
    required this.onToggleFav,
    required this.onContactTap,
    this.onViewedWithoutUnlock,
  });

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _candidateUid(Map<String, dynamic> data, String docId) =>
      OwnershipResolver.cvOwnerIdFromMap(data);

  Map<String, dynamic> _contacts(Map<String, dynamic> m) =>
      (m['contacts'] is Map)
      ? Map<String, dynamic>.from(m['contacts'])
      : <String, dynamic>{};
  Map<String, dynamic> _desired(Map<String, dynamic> m) => (m['desired'] is Map)
      ? Map<String, dynamic>.from(m['desired'])
      : <String, dynamic>{};

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  bool _activelyLooking(Map<String, dynamic> m, Map<String, dynamic> desired) {
    return (m['activelyLooking'] == true) ||
        (m['activeSearch'] == true) ||
        (m['searchingNow'] == true) ||
        (desired['activelyLooking'] == true) ||
        (desired['readyToWork'] == true);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final d = docs[i];
        final m = PublicCvSanitizer.sanitizePublicCv(d.data());
        final candidateUid = _candidateUid(m, d.id);
        final uid = OwnershipResolver.currentUid();
        final employerUid = uid.isNotEmpty ? uid : 'dev';
        final ownershipKnown = candidateUid.trim().isNotEmpty;
        final isOwnCandidate =
            ownershipKnown &&
            uid.trim().isNotEmpty &&
            uid.trim() == candidateUid.trim();

        final contacts = _contacts(m);
        final desired = _desired(m);
        final cvName = [
          _s(contacts['name']),
          '${_s(contacts['firstName'])} ${_s(contacts['lastName'])}'.trim(),
        ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
        final looking = _activelyLooking(m, desired);
        final viewedByEmployers = _asInt(
          m['employerViews'] ?? m['views'] ?? m['viewCount'],
        );
        final contactOpened = isContactOpened(d.id);

        final fav = isFav(d.id);

        void openDetails() {
          if (!contactOpened) {
            onViewedWithoutUnlock?.call(d.id);
          }
          CandidateDetailsSheet.open(
            context,
            candidateId: d.id,
            candidateUid: candidateUid,
            testMode: true,
          );
        }

        CandidateListCard buildCard(bool hasOfferSent) {
          return CandidateListCard(
            onTap: openDetails,
            onContactTap: (!ownershipKnown || isOwnCandidate || hasOfferSent)
                ? null
                : () => onContactTap(
                    candidateId: d.id,
                    candidateName: cvName,
                    openDetails: openDetails,
                  ),
            hasOfferSent: hasOfferSent,
            contactsOpened: contactOpened,
            name: '',
            ageText: '',
            birthDate: null,
            citizenshipCountry: '',
            profession: '',
            location: '',
            category: '',
            language: '',
            languagesData: const <Map<String, dynamic>>[],
            experience: '',
            drivingLicenseCategories: const <String>[],
            hasComputerSkills: false,
            hasTools: false,
            hasWorkwear: false,
            candidateId: d.id,
            candidateUid: candidateUid,
            candidateData: m,
            testMode: true,
            topRight: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () => onToggleFav(d.id, m),
              icon: Icon(
                fav ? Icons.star_rounded : Icons.star_border_rounded,
                color: fav ? WorkaColors.orange : WorkaColors.textGreyDark,
              ),
            ),
            statusBadge: null,
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (looking)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F7ED),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Активно ищет работу',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (looking) const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: openDetails,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: WorkaColors.blue, width: 1),
                    foregroundColor: WorkaColors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    isOwnCandidate ? 'Редактировать' : 'Подробнее',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (viewedByEmployers > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '🔥 $viewedByEmployers работодателей смотрели',
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        if (!ownershipKnown || isOwnCandidate) {
          return buildCard(false);
        }
        return CandidateOfferSentBuilder(
          employerUid: employerUid,
          candidateOwnerId: candidateUid,
          builder: (context, hasOffer) => buildCard(hasOffer),
        );
      },
    );
  }
}
