import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/widgets/cards/vacancy_list_card.dart';
import 'package:worka/widgets/favorite_star_button.dart';
import 'package:worka/widgets/worka_job_card.dart';
import 'package:worka/services/favorites_bus.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/repositories/jobs_repository.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/widgets/sent_overlay.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';

// search logic
import 'models/search_filters.dart';
import 'widgets/location_picker_sheet.dart';
import 'widgets/filters_sheet.dart';
import 'widgets/search_filters_config.dart';
import '../cv/widgets/cv_picker_sheet.dart';

// ✅ ПРАВИЛЬНЫЙ ПУТЬ к твоему sheet
import 'package:worka/screens/employer/search/widgets/vacancy_details_sheet.dart';
import 'package:worka/screens/vacancy_review_screen.dart';

// CV
import '../add_cv_screen.dart';

class SearchScreen extends StatefulWidget {
  final bool testMode;
  final bool embeddedInShell;

  const SearchScreen({
    super.key,
    this.testMode = true,
    this.embeddedInShell = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _qCtrl = TextEditingController();
  final _qFocus = FocusNode();

  SearchFilters _filters = SearchFilters.initial();

  static const _prefsKey = 'worka_favorites_job_ids';
  Set<String> _localFav = {};
  Set<String> _remoteFav = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteFavSub;
  StreamSubscription<void>? _favoritesBusSub;

  bool _showSuggest = false;

  @override
  void initState() {
    super.initState();
    _loadLocalFav();
    _listenRemoteFav();
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

  @override
  void dispose() {
    _remoteFavSub?.cancel();
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
        .collection('favorites')
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
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _localFav = list.toSet());
  }

  Future<void> _reloadFavoritesState() async {
    await _loadLocalFav();
    _listenRemoteFav();
  }

  Future<void> _saveLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _localFav.toList());
  }

  bool _isFav(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _localFav.contains(id);
    // When logged in, remote is the source of truth; local is only for guests.
    return _remoteFav.contains(id);
  }

  Future<void> _toggleFav(String id, Map<String, dynamic> jobData) async {
    final uid = _auth.currentUser?.uid;
    final nowFav = !_isFav(id);

    if (uid != null) {
      // Optimistic update on the remote set so the star flips instantly.
      setState(() {
        if (nowFav) {
          _remoteFav.add(id);
        } else {
          _remoteFav.remove(id);
        }
      });
    } else {
      setState(() {
        if (nowFav) {
          _localFav.add(id);
        } else {
          _localFav.remove(id);
        }
      });
      await _saveLocalFav();
    }

    if (uid != null) {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .doc(id);

      if (nowFav) {
        await ref.set({
          'jobId': id,
          'title': jobData['title'],
          'city': jobData['city'],
          'country': jobData['country'],
          'salary': jobData['salary'],
          'type': jobData['type'] ?? jobData['employmentType'],
          'category': jobData['category'],
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.delete();
      }
    }

    FavoritesBus.notify();
  }

  DateTime _dt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _sortJobsLocal(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    docs.sort((a, b) {
      final au = _dt(a.data()['updatedAt']);
      final bu = _dt(b.data()['updatedAt']);
      if (au != bu) return bu.compareTo(au);
      final ac = _dt(a.data()['createdAt']);
      final bc = _dt(b.data()['createdAt']);
      return bc.compareTo(ac);
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _jobsStream() {
    final stream = JobsRepository(
      _db,
    ).watchSearchJobs(testMode: widget.testMode);

    return stream.map((s) {
      final docs = [...s];
      _sortJobsLocal(docs);
      debugPrint(
        'Search jobs repo stream testMode=${widget.testMode}: ${docs.length}',
      );
      return docs;
    });
  }

  List<String> _suggestions(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final w in SearchFiltersConfig.keywordHints) {
      if (w.toLowerCase().contains(s)) out.add(w);
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<T?> _showTopSheet<T>({required Widget child}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: child,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, w) {
        final offset = Tween<Offset>(
          begin: const Offset(0, -0.12),
          end: Offset.zero,
        ).animate(anim);
        return SlideTransition(
          position: offset,
          child: FadeTransition(opacity: anim, child: w),
        );
      },
    );
  }

  Future<void> _openLocationPicker() async {
    final res = await _showTopSheet<LocationPickResult>(
      child: LocationPickerSheet(
        initialCountries: _filters.countries,
        initialCityLabel: _filters.cityLabel,
      ),
    );
    if (res == null) return;

    setState(() {
      _filters = _filters.copyWith(
        countries: res.countries, // ✅ Set<String>
        cityLabel: res.pickedCityLabel,
        clearCityLabel: res.pickedCityLabel == null,
      );
    });
  }

  Future<void> _openFilters() async {
    final res = await Navigator.push<SearchFilters>(
      context,
      MaterialPageRoute(builder: (_) => FiltersScreen(initial: _filters)),
    );
    if (res == null) return;
    setState(() => _filters = res);
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  bool _isUrgent(Map<String, dynamic> m) {
    final raw = m['isUrgent'];
    final isUrgentRaw =
        raw == true || (raw ?? '').toString().trim().toLowerCase() == 'срочно';
    if (!isUrgentRaw) return false;
    if (m['paidUrgent'] == true) return true;
    if (m['urgentActiveUntil'] != null) return true;
    return false;
  }

  double? _userSalaryThresholdEurPerMonth() {
    final eur = _filters.salaryFromEur;
    if (eur == null) return null;

    switch (_filters.salaryPeriod) {
      case 'В час':
        return eur * 160.0;
      case 'В день':
        return eur * 22.0;
      case 'В месяц':
      default:
        return eur;
    }
  }

  List<String> _tokenizeQuery(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return const [];
    return s
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _jobHaystack(Map<String, dynamic> m) {
    final title = _s(m['title']).toLowerCase();
    final desc = _s(m['description']).toLowerCase();
    final category = _s(m['category']).toLowerCase();
    final profession = _s(m['profession']).toLowerCase();
    final city = _s(m['city']).toLowerCase();
    final country = _s(m['country']).toLowerCase();

    final type = _s(m['type']).toLowerCase();
    final employmentType = _s(m['employmentType']).toLowerCase();
    final language = _s(m['language']).toLowerCase();
    final salary = _s(m['salary']).toLowerCase();

    final employer = (m['employer'] is Map)
        ? Map<String, dynamic>.from(m['employer'])
        : <String, dynamic>{};
    final companyName = _s(employer['companyName']).toLowerCase();

    return [
      title,
      desc,
      category,
      profession,
      city,
      country,
      type,
      employmentType,
      language,
      salary,
      companyName,
    ].join(' ');
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _applyFiltersAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final qTokens = _tokenizeQuery(_qCtrl.text);
    final cityLabel = (_filters.cityLabel ?? '').trim().toLowerCase();
    final hasLocationFilter = cityLabel.isNotEmpty;
    final salaryThreshold = _userSalaryThresholdEurPerMonth();

    bool matchKeywords(Map<String, dynamic> m) {
      if (qTokens.isEmpty) return true;
      final hay = _jobHaystack(m);
      for (final w in qTokens) {
        if (!hay.contains(w)) return false;
      }
      return true;
    }

    bool matchLocation(Map<String, dynamic> m) {
      if (hasLocationFilter) {
        final city = _s(m['city']).toLowerCase();
        final country = _s(m['country']).toLowerCase();
        final label = '$city • $country';
        return label.contains(cityLabel) ||
            city.contains(cityLabel) ||
            country.contains(cityLabel);
      }

      if (_filters.countries.isEmpty) return true;

      final c = _s(m['country']);
      if (c.isEmpty) return true;

      return _filters.countries.contains(c);
    }

    bool matchCategory(Map<String, dynamic> m) {
      if (_filters.categories.isEmpty) return true;
      final v = _s(m['category']);
      if (v.isEmpty) return false;
      return _filters.categories.contains(v);
    }

    bool matchEmployment(Map<String, dynamic> m) {
      if (_filters.employment.isEmpty) return true;

      final v1 = _s(m['employmentType']);
      final v2 = _s(m['type']);
      final v = v1.isNotEmpty ? v1 : v2;

      if (v.isEmpty) return true;
      return _filters.employment.contains(v);
    }

    bool matchExperience(Map<String, dynamic> m) {
      if (_filters.experience.isEmpty) return true;
      final v = _s(m['experience']);
      if (v.isEmpty) return true;
      return _filters.experience.contains(v);
    }

    bool matchLanguages(Map<String, dynamic> m) {
      if (_filters.languages.isEmpty) return true;

      final v = _s(m['language']);
      if (_filters.languages.contains('Без языка')) {
        if (v.isEmpty) return true;
      }
      if (v.isEmpty) return false;
      return _filters.languages.contains(v);
    }

    bool matchSwitches(Map<String, dynamic> m) {
      if (_filters.housing && m['housingProvided'] != true) return false;
      if (_filters.transport && m['transportProvided'] != true) return false;
      if (_filters.teen && m['teenFriendly'] != true) return false;
      if (_filters.disability && m['disabilityFriendly'] != true) return false;
      if (_filters.helpsWithDocuments) {
        final helps =
            (m['helpsWithDocuments'] == true) ||
            (m['documentsSupport'] == true) ||
            (m['documentsHelp'] == true);
        if (!helps) return false;
      }
      if (_filters.noLanguageRequired) {
        final noLanguage =
            (m['noLanguageRequired'] == true) ||
            (m['languageRequired'] == false) ||
            _s(m['language']).isEmpty ||
            _s(m['language']).toLowerCase() == 'без языка';
        if (!noLanguage) return false;
      }
      return true;
    }

    final pre = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final m = d.data();
      if (!matchKeywords(m)) continue;
      if (!matchLocation(m)) continue;
      if (!matchCategory(m)) continue;
      if (!matchEmployment(m)) continue;
      if (!matchExperience(m)) continue;
      if (!matchLanguages(m)) continue;
      if (!matchSwitches(m)) continue;
      pre.add(d);
    }

    int urgentScore(Map<String, dynamic> m) => _isUrgent(m) ? 1 : 0;

    if (salaryThreshold == null) {
      pre.sort(
        (a, b) => urgentScore(b.data()).compareTo(urgentScore(a.data())),
      );
      return pre;
    }

    // если включен salaryThreshold — сравниваем через поле salaryEurPerMonth если есть (быстрее)
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in pre) {
      final m = d.data();
      final eurMonth = (m['salaryEurPerMonth'] is num)
          ? (m['salaryEurPerMonth'] as num).toDouble()
          : null;
      if (eurMonth == null) continue;
      if (eurMonth >= salaryThreshold) out.add(d);
    }

    out.sort((a, b) => urgentScore(b.data()).compareTo(urgentScore(a.data())));
    return out;
  }

  Widget _emptyJobsMessage() {
    final baseStyle = const TextStyle(
      fontWeight: FontWeight.w800,
      color: WorkaColors.textGreyDark,
      height: 1.25,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: baseStyle,
            children: [
              const TextSpan(
                text:
                    'К сожалению, по вашим параметрам ничего не найдено, попробуйте изменить параметры поиска или ',
              ),
              TextSpan(
                text: 'добавьте свое CV',
                style: baseStyle.copyWith(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddCvScreen()),
                    );
                  },
              ),
              const TextSpan(
                text: ' чтобы работодатели могли связаться с вами',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A6FDB), Color(0xFF5B7FE8)],
        ),
      ),
      child: SafeArea(
        top: !widget.embeddedInShell,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.menu, color: Colors.white, size: 28),
                  const Text(
                    'Worka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Stack(
                    children: [
                      const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFA500),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: TextField(
                        controller: _qCtrl,
                        focusNode: _qFocus,
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Найти работу',
                          hintStyle: TextStyle(
                            color: Color(0xFFAAAAAA),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Color(0xFFAAAAAA),
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: InputBorder.none,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilters,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.tune,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip('Местоположение', onTap: _openLocationPicker),
          _filterChip('Зарплата', onTap: _openFilters),
          _filterChip('Полная занятость', onTap: _openFilters),
          _filterChip('Ещё фильтры', onTap: _openFilters),
        ],
      ),
    );
  }

  Widget _filterChip(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildGradientHeader(context),
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
                if (_showSuggest)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _SuggestBox(
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
                  ),
                _buildFilterChips(),
                const SizedBox(height: 8),
                Expanded(
                  child:
                      StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      >(
                        stream: _jobsStream(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(child: Text('Ошибка: ${snap.error}'));
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          }

                          final docs = snap.data!;

                          return FutureBuilder<
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          >(
                            future: _applyFiltersAsync(docs),
                            builder: (context, filteredSnap) {
                              if (filteredSnap.hasError) {
                                return Center(
                                  child: Text('Ошибка: ${filteredSnap.error}'),
                                );
                              }
                              // Show spinner only on first load (no previous
                              // data yet). Subsequent Firestore updates keep
                              // showing the old list so scrolling isn't
                              // interrupted.
                              if (filteredSnap.data == null) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }

                              final filtered = filteredSnap.data!;
                              if (filtered.isEmpty) return _emptyJobsMessage();

                              return _JobsList(
                                docs: filtered,
                                isFav: _isFav,
                                onToggleFav: _toggleFav,
                                testMode: widget.testMode,
                              );
                            },
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embeddedInShell) {
      return content;
    }

    return Scaffold(backgroundColor: const Color(0xFF4A6FDB), body: content);
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
            hoverColor: WorkaColors.hoverBlue,
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

class _JobsList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool Function(String id) isFav;
  final Future<void> Function(String id, Map<String, dynamic> data) onToggleFav;
  final bool testMode;

  const _JobsList({
    required this.docs,
    required this.isFav,
    required this.onToggleFav,
    this.testMode = true,
  });

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  double? _d(dynamic v) {
    if (v is num) return v.toDouble();
    final t = (v ?? '').toString().trim().replaceAll(',', '.');
    return double.tryParse(t);
  }

  String _ownerFrom(Map<String, dynamic> data) =>
      OwnershipResolver.vacancyOwnerIdFromMap(data);

  bool _isUrgent(Map<String, dynamic> m) {
    final raw = m['isUrgent'];
    final isUrgentRaw =
        raw == true || (raw ?? '').toString().trim().toLowerCase() == 'срочно';
    if (!isUrgentRaw) return false;
    if (m['paidUrgent'] == true) return true;
    if (m['urgentActiveUntil'] != null) return true;
    return false;
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = (v ?? '').toString().trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'yes' || t == 'да';
  }

  bool _hasVerifiedEmployerFlag(Map<String, dynamic> m) {
    return m.containsKey('verifiedEmployer') ||
        m.containsKey('isVerified') ||
        m.containsKey('employerVerified') ||
        m.containsKey('verified');
  }

  bool _verifiedEmployerForCard(String jobId, Map<String, dynamic> m) {
    final fromData =
        _asBool(m['verifiedEmployer']) ||
        _asBool(m['isVerified']) ||
        _asBool(m['employerVerified']) ||
        _asBool(m['verified']);
    if (fromData) return true;
    if (_hasVerifiedEmployerFlag(m)) return false;
    // Для demo/mock показываем только на части карточек.
    return testMode && jobId.hashCode.abs() % 4 == 0;
  }

  Future<void> _quickApplyToJob({
    required BuildContext context,
    required String jobId,
    required Map<String, dynamic> jobData,
  }) async {
    final db = FirebaseFirestore.instance;

    try {
      await VacancyApplyEntrySheet.open(
        context,
        vacancy: jobData,
        onSendCvTap: () async {
          if (!AuthGuard.ensureSignedIn(context)) return false;
          final uid = (AuthGuard.effectiveUidOrNull() ?? '').trim();
          if (uid.isEmpty) return false;

          final cvSnap = await db
              .collection(FirestorePaths.cvs)
              .where('ownerId', isEqualTo: uid)
              .get();
          final cvs = cvSnap.docs
              .where(
                (d) =>
                    WorkaEntityValidity.isValidOwnerCv(d.data(), ownerUid: uid),
              )
              .toList();

          if (cvs.isEmpty) {
            if (!context.mounted) return false;
            await Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute(builder: (_) => const AddCvScreen()));
            return false;
          }

          String selectedCvId;
          if (cvs.length == 1) {
            selectedCvId = cvs.first.id;
          } else {
            if (!context.mounted) return false;
            final picked = await CvPickerSheet.open(
              context,
              title: 'Выберите CV',
              allowCreate: true,
              forceTestCollection: testMode,
            );
            if (picked == null) return false;
            selectedCvId = picked.cvId;
          }

          final ownerId = _ownerFrom(jobData);
          if (ownerId.isEmpty) {
            if (!context.mounted) return false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось определить владельца вакансии'),
              ),
            );
            return false;
          }

          await ResponseRepository(db).createApply(
            jobId: jobId,
            jobOwnerId: ownerId,
            candidateCvId: selectedCvId,
            candidateOwnerId: uid,
            applicantProfileType: AppMode.currentMode == AccountMode.business
                ? 'business'
                : 'personal',
          );
          if (!context.mounted) return false;
          await showSentOverlay(context, 'Отклик отправлен');
          return true;
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
    }
  }

  Widget _ownerActions(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VacancyReviewScreen(
                jobId: doc.id,
                jobRef: doc.reference,
                testMode: testMode,
              ),
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF2F5BFF)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Редактировать',
            style: TextStyle(
              color: Color(0xFF2F5BFF),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => VacancyDetailsSheet.open(
            context,
            jobId: doc.id,
            asWorker: false,
            testMode: testMode,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: WorkaColors.orange,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Готово',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final d = docs[i];
        final m = d.data();

        final title = _s(m['title'], fallback: 'Вакансия');
        final city = _s(m['city']);
        final country = _s(m['country']);
        final salaryFrom = _d(m['salaryFrom'] ?? m['salaryAmount']);
        final salaryTo = _d(m['salaryTo']);
        final salaryType = _s(
          m['salaryType'],
          fallback: _s(m['salaryPeriod'], fallback: 'month'),
        );
        final salaryTextFallback = _s(
          m['salaryText'],
          fallback: _s(m['salary'], fallback: 'По договорённости'),
        );
        final employmentLabel = _s(
          m['workSchedule'],
          fallback: _s(
            m['workScheduleOption'],
            fallback: _s(
              m['employmentType'],
              fallback: _s(m['type'], fallback: 'Полная занятость'),
            ),
          ),
        );
        final housingProvided = m['housingProvided'] == true;
        final transportProvided = m['transportProvided'] == true;
        final forTeenagers =
            m['forTeenagers'] == true || m['teenFriendly'] == true;
        final forDisabled =
            m['forDisabled'] == true || m['disabledFriendly'] == true;
        final isUrgent = _isUrgent(m);
        final noLanguageRequired =
            m['noLanguageRequired'] == true ||
            _s(m['language']).toLowerCase() == 'без языка';
        final noExperienceRequired =
            _s(m['experience']).toLowerCase().contains('без') &&
                _s(m['experience']).toLowerCase().contains('опыт') ||
            _s(m['experienceRequired']).toLowerCase() == 'no_experience';
        final verifiedEmployer = _verifiedEmployerForCard(d.id, m);

        final fav = isFav(d.id);
        final currentUserId = OwnershipResolver.currentUid();
        final ownerId = _ownerFrom(m);
        final ownership = OwnershipResolver.byOwnerId(
          ownerId,
          currentUserId: currentUserId,
        );
        final isMine = ownership.known && ownership.isOwner;
        return VacancyListCard(
          mode: WorkaJobCardMode.marketplace,
          title: title,
          city: city,
          country: country,
          salaryFrom: salaryFrom,
          salaryTo: salaryTo,
          salaryType: salaryType,
          salaryTextFallback: salaryTextFallback,
          employmentLabel: employmentLabel,
          housingProvided: housingProvided,
          transportProvided: transportProvided,
          forTeenagers: forTeenagers,
          forDisabled: forDisabled,
          isUrgent: isUrgent,
          jobId: d.id,
          candidateOwnerId: currentUserId,
          ownerUid: ownerId,
          ownerEmail: _s(
            m['ownerEmail'],
            fallback: _s(m['email'], fallback: _s(m['contactEmail'])),
          ),
          onTap: isMine
              ? () => VacancyDetailsSheet.open(
                  context,
                  jobId: d.id,
                  asWorker: false,
                  testMode: testMode,
                )
              : () =>
                    _quickApplyToJob(context: context, jobId: d.id, jobData: m),
          onApply: isMine
              ? null
              : () =>
                    _quickApplyToJob(context: context, jobId: d.id, jobData: m),
          showApply: !isMine,
          bottomRight: isMine ? _ownerActions(context, doc: d) : null,
          topRight: FavoriteStarButton(
            isFavorite: fav,
            onTap: () => onToggleFav(d.id, m),
            tooltip: fav ? 'Убрать из избранного' : 'В избранное',
            size: 30,
          ),
          noLanguageRequired: noLanguageRequired,
          noExperienceRequired: noExperienceRequired,
          verifiedEmployer: verifiedEmployer,
        );
      },
    );
  }
}
